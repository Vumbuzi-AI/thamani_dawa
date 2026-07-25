defmodule ThamaniDawa.Accounts do
  @moduledoc """
  Users, sessions, and staff invites. Every function that reads or writes a
  user is scoped to an `organization_id`, except lookups keyed on the
  globally-unique `email` (see §2.2 of project.md).
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Accounts.{Scope, User, UserLoginSession, UserNotifier, UserToken}
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites.Site

  ## Users

  @doc "Gets a user by email, across the whole platform (email is globally unique)."
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
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
    Repo.get_by!(User, id: id, organization_id: organization_id)
    |> Repo.preload(sites: scoped_site_query(organization_id))
  end

  @doc "Lists an organization's staff, for the Team screen. Preloads `sites` (scoped to the organization)."
  def list_users(organization_id) do
    Repo.all(
      from u in User,
        where: u.organization_id == ^organization_id,
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
  Registers the first admin of a brand-new organization. `organization_id`
  is always taken as an explicit argument, never from `attrs`, and the role
  is always `:admin` — a caller can never register a user into someone
  else's organization or with a different role. Used by
  `ThamaniDawa.Organizations.signup/2`.
  """
  def register_user(organization_id, attrs) when is_integer(organization_id) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Ecto.Changeset.put_change(:role, :admin)
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
  validated to belong to that organization. If the user's current site is no
  longer among their assigned sites, it's reset to the first remaining site
  (or `nil`).
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
      |> maybe_reset_current_site(user, sites)

    Repo.update(changeset)
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

  defp default_current_site_id([]), do: nil
  defp default_current_site_id([site | _]), do: site.id

  defp maybe_reset_current_site(changeset, %User{current_site_id: current_site_id}, sites) do
    if is_nil(current_site_id) or current_site_id in Enum.map(sites, & &1.id) do
      changeset
    else
      Ecto.Changeset.put_change(changeset, :current_site_id, default_current_site_id(sites))
    end
  end

  @doc """
  Switches the signed-in user to one of their assigned sites (or `nil`, for
  an org-wide admin). Rejects a site the user isn't assigned to.
  """
  def switch_current_site(%Scope{user: %User{} = user}, site_id) do
    user = Repo.preload(user, :sites)
    allowed_ids = Enum.map(user.sites, & &1.id)

    if is_nil(site_id) or site_id in allowed_ids do
      user
      |> User.switch_site_changeset(%{current_site_id: site_id})
      |> Repo.update()
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
  outstanding invite token for them.
  """
  def accept_invite(%User{} = user, attrs) do
    Repo.transaction(fn ->
      case user |> User.accept_invite_changeset(attrs) |> Repo.update() do
        {:ok, user} ->
          Repo.delete_all(UserToken.by_user_and_context_query(user, "invite"))
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
    Repo.insert!(user_token)
    token
  end

  @doc "Gets the user for a given session token. Preloads `sites` (needed for the site switcher on every authenticated page)."
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    query |> Repo.one() |> maybe_preload_sites()
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
