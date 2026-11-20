defmodule ThamaniDawa.Accounts do
  @moduledoc """
  Users, sessions, and staff invites. Every function that reads or writes a
  user is scoped to an `organization_id`, except lookups keyed on the
  globally-unique `email` (see §2.2 of project.md).
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Accounts.{Scope, User, UserLoginSession, UserNotifier, UserSite, UserToken}
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site

  ## Users

  @doc "Gets a user by email, across the whole platform (email is globally unique)."
  def get_user_by_email(email) when is_binary(email) do
    normalized_email = email |> String.trim() |> String.downcase()

    Repo.one(
      from u in User,
        where: fragment("lower(?)", u.email) == ^normalized_email
    )
  end

  @doc """
  Gets a user by email and password, across the whole platform.
  Returns `nil` if the user is not found, deactivated, or the password is incorrect.
  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)
    if User.valid_password?(user, password) and User.active?(user), do: user
  end

  @doc "Gets a single user scoped to an organization. Raises if not found. Preloads `sites` (scoped to the organization)."
  def get_user!(organization_id, id) do
    user = Repo.get_by!(User, id: id, organization_id: organization_id)
    Repo.preload(user, sites: scoped_site_query(organization_id))
  end

  @doc "Lists an organization's staff, for the Team screen. Preloads `sites` (scoped to the organization)."
  def list_users(organization_id) do
    Repo.all(
      from u in User,
        where: u.organization_id == ^organization_id,
        preload: [sites: ^scoped_site_query(organization_id)]
    )
  end

  @doc "Lists an organization's active admins — who to notify of org-wide events like recalls."
  def list_admins(organization_id) do
    Repo.all(
      from u in User,
        where: u.organization_id == ^organization_id,
        where: u.is_active,
        where: ^:admin in u.roles
    )
  end

  @doc "Lists outstanding staff invitations for an organization, newest first."
  def list_pending_invites(organization_id) do
    Repo.all(
      from u in User,
        where:
          u.organization_id == ^organization_id and is_nil(u.hashed_password) and
            not is_nil(u.invited_by_id),
        order_by: [desc: u.inserted_at],
        preload: [sites: ^scoped_site_query(organization_id)]
    )
  end

  @doc "Lists everyone invited into an organization, newest first, accepted or not."
  def list_invited_users(organization_id) do
    Repo.all(
      from u in User,
        where: u.organization_id == ^organization_id and not is_nil(u.invited_by_id),
        order_by: [desc: u.inserted_at],
        preload: [sites: ^scoped_site_query(organization_id)]
    )
  end

  @doc "Lists an organization's staff with pagination. Preloads `sites` (scoped to the organization)."
  def list_users_paginated(organization_id, page \\ 1) do
    from(u in User,
      where: u.organization_id == ^organization_id,
      preload: [sites: ^scoped_site_query(organization_id)]
    )
    |> Repo.paginate(page: page)
  end

  defp scoped_site_query(organization_id) do
    from s in Site, where: s.organization_id == ^organization_id
  end

  @doc """
  Lists the staff assigned to a single site, for the site detail page's
  "Staff assigned" card. Returns plain `%{id:, name:, role:}` maps (not
  `User` structs), ordered by name.
  """
  def list_users_for_site(organization_id, site_id) do
    from(u in User,
      join: us in UserSite,
      on: us.user_id == u.id,
      where: us.organization_id == ^organization_id and us.site_id == ^site_id,
      order_by: [asc: u.name],
      select: %{id: u.id, name: u.name, roles: u.roles}
    )
    |> Repo.all()
  end

  @doc """
  Registers the first admin of a brand-new organization. `organization_id`
  is always taken as an explicit argument, never from `attrs`, and the role
  is always `:admin` plus whichever operational roles the organization's
  `operating_models` imply (see `operational_roles/1`) — a caller can never
  register a user into someone else's organization or with an unrelated
  role. Used by `ThamaniDawa.Organizations.signup/3`.

  Granting the operational roles up front (rather than leaving the admin to
  invite themselves separately) is what makes the sidebar's workspace
  switcher and the distributor portal reachable immediately after signup —
  both key off `:pharmacist`/`:lab_technician`/`:distributor` roles, not the
  organization's `operating_models` directly.
  """
  def register_user(organization_id, attrs, operating_models \\ [])
      when is_integer(organization_id) do
    roles = Enum.uniq([:admin | operational_roles(operating_models)])

    %User{}
    |> User.registration_changeset(attrs, require_legal_consent: true)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Ecto.Changeset.put_change(:roles, roles)
    |> Repo.insert()
  end

  defp operational_roles(models) do
    Enum.flat_map(models, fn
      :pharmacy -> [:pharmacist]
      :laboratory -> [:lab_technician]
      :distributor -> [:distributor]
      _ -> []
    end)
  end

  @doc """
  Creates a platform-only superadmin account.

  This is intentionally not reachable through signup or organization invites:
  platform operators do not belong to a tenant and never receive a tenant role.
  """
  def create_platform_superadmin(attrs) when is_map(attrs) do
    %User{}
    |> User.registration_changeset(attrs, require_legal_consent: true)
    |> Ecto.Changeset.put_change(:roles, [:superadmin])
    |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.insert()
  end

  ## Invites (§2.3.2, §7)

  @doc """
  Invites a staff member into `organization_id`. Creates an unconfirmed
  `users` row (no password yet) and returns a one-time invite token
  alongside it — the caller is responsible for emailing it via
  `deliver_user_invite/5`. `organization_id` and `invited_by_id` are always
  explicit arguments, never taken from `attrs`, so an admin can only invite
  staff into their own organization; `attrs["site_ids"]` (or `attrs[:site_ids]`)
  is resolved to `Site`s and validated to belong to that same organization.
  `current_site_id` defaults to the first assigned site (or `nil` for an
  org-wide admin with no sites).
  """
  def invite_user(organization_id, invited_by_id, attrs) when is_integer(organization_id) do
    site_ids = extract_site_ids(attrs)
    sites = list_sites_by_ids(organization_id, site_ids)

    changeset =
      %User{sites: []}
      |> User.invite_changeset(attrs)
      |> Ecto.Changeset.put_change(:organization_id, organization_id)
      |> Ecto.Changeset.put_change(:invited_by_id, invited_by_id)
      |> Ecto.Changeset.put_assoc(:sites, sites)
      |> validate_sites_resolved(site_ids, sites)
      |> validate_sites_role_compatible()
      |> Ecto.Changeset.put_change(:current_site_id, default_current_site_id(sites))

    case Repo.insert(changeset) do
      {:ok, user} ->
        {encoded_token, user_token} = UserToken.build_email_token(user, "invite")
        Repo.insert!(user_token)
        {:ok, user, encoded_token}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Updates a team member's role and site assignment. `organization_id` is
  validated to ensure the user belongs to the same organization, and
  `attrs["site_ids"]` (or `attrs[:site_ids]`) is resolved to `Site`s and
  validated to belong to that organization. If the user has no current site,
  or their current site is no longer among their assigned sites, it's (re)set
  to the first assigned site (or `nil` if they now have none) — so a user
  invited without a site, then later assigned one, isn't stuck forever
  without a `current_site_id`.
  """
  def update_user(organization_id, user_id, attrs) when is_integer(organization_id) do
    user = organization_id |> get_user!(user_id)
    site_ids = extract_site_ids(attrs)
    sites = list_sites_by_ids(organization_id, site_ids)

    changeset =
      user
      |> User.edit_changeset(attrs)
      |> Ecto.Changeset.put_assoc(:sites, sites)
      |> validate_sites_resolved(site_ids, sites)
      |> validate_sites_role_compatible()
      |> maybe_reset_current_site(user, sites)

    Repo.audited_update(changeset)
  end

  @doc """
  Activates or deactivates a team member within an organization.

  An administrator cannot deactivate their own account or the organization's
  last active administrator.
  """
  def set_user_active(organization_id, acting_user_id, user_id, active?)
      when is_integer(organization_id) and is_integer(acting_user_id) and
             is_integer(user_id) and is_boolean(active?) do
    result =
      Repo.transaction(fn ->
        lock_active_admins(organization_id)
        acting_user = get_user!(organization_id, acting_user_id)
        user = get_user!(organization_id, user_id)
        do_set_user_active(organization_id, acting_user, user, acting_user_id, active?)
      end)

    case result do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_set_user_active(organization_id, acting_user, user, acting_user_id, active?) do
    with :ok <- authorize_account_status_change(acting_user),
         :ok <- validate_account_status_change(user, acting_user_id, active?),
         :ok <- preserve_active_admin(organization_id, user, active?) do
      user
      |> Ecto.Changeset.change(is_active: active?)
      |> Repo.audited_update()
    else
      {:unchanged, user} -> {:ok, user}
      {:error, reason} -> {:error, reason}
    end
  end

  defp authorize_account_status_change(%User{roles: roles, is_active: true}) do
    if :admin in roles, do: :ok, else: {:error, :unauthorized}
  end

  defp authorize_account_status_change(_user), do: {:error, :unauthorized}

  defp validate_account_status_change(%User{is_active: active?} = user, _acting_id, active?),
    do: {:unchanged, user}

  defp validate_account_status_change(%User{id: id}, id, false),
    do: {:error, :cannot_deactivate_self}

  defp validate_account_status_change(_user, _acting_id, _active?), do: :ok

  defp preserve_active_admin(organization_id, %User{roles: roles}, false) do
    if :admin in roles and last_active_admin?(organization_id),
      do: {:error, :last_active_admin},
      else: :ok
  end

  defp preserve_active_admin(_organization_id, _user, _active?), do: :ok

  defp lock_active_admins(organization_id) do
    from(u in User,
      where:
        u.organization_id == ^organization_id and u.is_active == true and
          fragment("? @> ?", u.roles, ^["admin"]),
      lock: "FOR UPDATE"
    )
    |> Repo.all()
  end

  defp last_active_admin?(organization_id) do
    Repo.aggregate(
      from(u in User,
        where:
          u.organization_id == ^organization_id and u.is_active == true and
            fragment("? @> ?", u.roles, ^["admin"])
      ),
      :count
    ) <= 1
  end

  defp extract_site_ids(attrs) do
    (Map.get(attrs, :site_ids) || Map.get(attrs, "site_ids") || [])
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map(&to_site_id/1)
    |> Enum.uniq()
  end

  defp to_site_id(id) when is_integer(id), do: id
  defp to_site_id(id) when is_binary(id), do: String.to_integer(id)

  defp list_sites_by_ids(_organization_id, []), do: []

  defp list_sites_by_ids(organization_id, site_ids) do
    Repo.all(from s in Site, where: s.id in ^site_ids and s.organization_id == ^organization_id)
  end

  defp validate_sites_resolved(changeset, site_ids, sites) do
    if length(sites) == length(site_ids) do
      changeset
    else
      Ecto.Changeset.add_error(changeset, :sites, "must belong to the same organization")
    end
  end

  # A site a role can't operate (a pharmacist at a warehouse-only site)
  # would strand that staff member at a location whose panel none of their
  # roles can enter — the sidebar picker filters these out too, so they'd
  # be stuck with no way to switch. Reject the assignment at the source.
  defp validate_sites_role_compatible(changeset) do
    roles = Ecto.Changeset.get_field(changeset, :roles) || []
    sites = Ecto.Changeset.get_field(changeset, :sites) || []

    incompatible = Enum.reject(sites, &Site.role_compatible?(roles, &1))

    case incompatible do
      [] ->
        changeset

      sites ->
        names = Enum.map_join(sites, ", ", & &1.name)

        Ecto.Changeset.add_error(
          changeset,
          :sites,
          "can't include #{names} — this site's activities don't match the selected roles"
        )
    end
  end

  defp default_current_site_id([]), do: nil
  defp default_current_site_id([site | _]), do: site.id

  defp maybe_reset_current_site(changeset, %User{current_site_id: current_site_id}, sites) do
    roles = Ecto.Changeset.get_field(changeset, :roles) || []
    current_site = Enum.find(sites, &(&1.id == current_site_id))

    if current_site && Site.role_compatible?(roles, current_site) do
      changeset
    else
      Ecto.Changeset.put_change(changeset, :current_site_id, default_current_site_id(sites))
    end
  end

  @doc """
  Lists the sites a user belongs to.
  """
  def list_sites_for_user(%Scope{organization_id: org_id} = scope) do
    if Scope.admin?(scope) do
      Sites.list_sites(org_id)
    else
      list_sites_for_user(scope.user)
    end
  end

  def list_sites_for_user(%User{roles: roles, organization_id: org_id} = user) do
    if :admin in roles do
      Sites.list_sites(org_id)
    else
      user = Repo.preload(user, :sites)
      user.sites
    end
  end

  def list_sites_for_user(nil), do: []

  def list_sites_for_user(organization_id, user_id)
      when is_integer(organization_id) and is_integer(user_id) do
    user = get_user!(organization_id, user_id)
    list_sites_for_user(user)
  end

  @doc """
  Switches the signed-in user to one of their assigned sites (or `nil`, for
  an org-wide admin). Rejects a site the user isn't assigned to — unless
  they're an admin, who may switch to any of the organization's sites, not
  just the ones they happen to hold a `UserSite` row for.
  """
  def switch_current_site(%Scope{user: %User{} = user} = scope, site_id) do
    user = Repo.preload(user, :sites)

    allowed_ids =
      if Scope.admin?(scope) do
        scope.organization_id |> Sites.list_sites() |> Enum.map(& &1.id)
      else
        Enum.map(user.sites, & &1.id)
      end

    if is_nil(site_id) or site_id in allowed_ids do
      user
      |> User.switch_site_changeset(%{current_site_id: site_id})
      |> Repo.audited_update()
    else
      {:error, :not_assigned}
    end
  end

  @doc """
  Emails the invite link to a newly-invited user.
  """
  def deliver_user_invite(
        %User{} = user,
        organization_name,
        invited_by_name,
        encoded_token,
        invite_url_fun
      )
      when is_function(invite_url_fun, 1) do
    UserNotifier.deliver_invite(
      user,
      organization_name,
      invited_by_name,
      invite_url_fun.(encoded_token)
    )
  end

  @doc "Gets the invited user for a given (unexpired, unused) invite token, or nil."
  def get_user_by_invite_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "invite"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Accepts an invite: sets the invited user's password and invalidates every
  outstanding invite token for them. Setting a password from a one-time
  emailed link already proves they own the address, so this also confirms
  their email — invited staff never see the separate confirm-email gate
  self-signed-up admins do.
  """
  def accept_invite(%User{} = user, attrs) do
    Repo.transaction(fn ->
      changeset =
        user
        |> User.accept_invite_changeset(attrs)
        |> Ecto.Changeset.put_change(
          :confirmed_at,
          DateTime.utc_now() |> DateTime.truncate(:second)
        )

      case Repo.update(changeset) do
        {:ok, user} ->
          Repo.delete_all(UserToken.by_user_and_context_query(user, "invite"))
          user

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Sends a one-time email-confirmation link, mirroring the invite/
  reset-password token pattern. Replaces any outstanding confirm token for
  this user first, so an old link in a previous email stops working once a
  new one is sent.
  """
  def deliver_user_confirmation_instructions(%User{} = user, confirm_url_fun)
      when is_function(confirm_url_fun, 1) do
    Repo.transaction(fn ->
      Repo.delete_all(UserToken.by_user_and_context_query(user, "confirm"))
      {encoded_token, token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(token)

      case UserNotifier.deliver_confirmation_instructions(user, confirm_url_fun.(encoded_token)) do
        {:ok, _email} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "Gets the user for a valid (unexpired) confirm token, or nil."
  def get_user_by_confirm_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Confirms a user's email from a confirm token, invalidating every
  outstanding confirm token for them. Returns `{:error, :invalid_token}` for
  an unknown/expired token rather than raising, since this is called from a
  link a user clicked that could easily be stale.
  """
  def confirm_user(token) do
    case get_user_by_confirm_token(token) do
      nil ->
        {:error, :invalid_token}

      user ->
        Repo.transaction(fn ->
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          case user |> Ecto.Changeset.change(confirmed_at: now) |> Repo.update() do
            {:ok, user} ->
              Repo.delete_all(UserToken.by_user_and_context_query(user, "confirm"))
              user

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)
    end
  end

  @doc "Sends a reset link when an active account exists; callers always receive :ok."
  def deliver_password_reset_instructions(email, reset_url_fun)
      when is_function(reset_url_fun, 1) do
    case get_user_by_email(email) do
      %User{is_active: true} = user ->
        deliver_reset_password_token(user, reset_url_fun)

      _ ->
        {:ok, :ignored}
    end
  end

  defp deliver_reset_password_token(user, reset_url_fun) do
    Repo.transaction(fn ->
      Repo.delete_all(UserToken.by_user_and_context_query(user, "reset_password"))
      {encoded_token, token} = UserToken.build_email_token(user, "reset_password")
      Repo.insert!(token)
      deliver_reset_password_email(user, reset_url_fun.(encoded_token))
    end)
  end

  defp deliver_reset_password_email(user, url) do
    case UserNotifier.deliver_password_reset(user, url) do
      {:ok, _email} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc "Gets an active user for a valid reset-password token."
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{is_active: true} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc "Resets a password and invalidates reset links and existing sessions."
  def reset_password(%User{} = user, attrs) do
    Repo.transaction(fn ->
      case user |> User.password_reset_changeset(attrs) |> Repo.update() do
        {:ok, user} ->
          Repo.delete_all(UserToken.by_user_and_context_query(user, "reset_password"))
          Repo.delete_all(UserToken.by_user_and_context_query(user, "session"))
          user

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  ## PIN (secondary auth, §7)

  @doc "Sets or changes a user's 4-digit counter-side PIN."
  def set_user_pin(%User{} = user, attrs) do
    user
    |> User.pin_changeset(attrs)
    |> Repo.update()
  end

  @doc "Verifies a plaintext PIN against the given user's stored hash."
  def valid_pin?(%User{} = user, pin), do: User.valid_pin?(user, pin)

  ## Session

  @doc "Generates a session token for the given user."
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(%{user_token | last_used_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    token
  end

  @doc "Gets the user for a given session token. Preloads `sites` (needed for the site switcher on every authenticated page)."
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    query |> Repo.one() |> maybe_preload_sites()
  end

  @doc "Records activity for a valid session token without extending its absolute lifetime."
  def touch_user_session(token) when is_binary(token) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    query = UserToken.by_token_and_context_query(token, "session")
    Repo.update_all(query, set: [last_used_at: now])

    :ok
  end

  defp maybe_preload_sites(nil), do: nil
  defp maybe_preload_sites(%User{} = user), do: Repo.preload(user, :sites)

  @doc "Deletes the given session token."
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  @doc "Stamps `last_logged_in_at` on the given user to now."
  def update_user_last_logged_in(%User{} = user) do
    user
    |> Ecto.Changeset.change(%{
      last_logged_in_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc "Stamps `last_logged_out_at` on the given user to now."
  def update_user_last_logged_out(%User{} = user) do
    user
    |> Ecto.Changeset.change(%{
      last_logged_out_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc "Creates a `user_login_sessions` row recording a fresh login for `user_id`."
  def create_login_session(user_id) do
    %UserLoginSession{}
    |> UserLoginSession.changeset(%{
      user_id: user_id,
      logged_in_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert()
  end

  @doc """
  Records logout on `user_id`'s most recent still-open login session (the
  one with no `logged_out_at` yet). No-op if there isn't one.
  """
  def record_logout_session(user_id) do
    session =
      UserLoginSession
      |> where([s], s.user_id == ^user_id and is_nil(s.logged_out_at))
      |> order_by([s], desc: s.logged_in_at)
      |> limit(1)
      |> Repo.one()

    if session do
      session
      |> UserLoginSession.changeset(%{
        logged_out_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update()
    end
  end
end
