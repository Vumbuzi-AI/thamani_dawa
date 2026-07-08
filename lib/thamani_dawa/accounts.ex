defmodule ThamaniDawa.Accounts do
  @moduledoc """
  Users, sessions, and staff invites. Every function that reads or writes a
  user is scoped to an `organization_id`, except lookups keyed on the
  globally-unique `email` (see §2.2 of project.md).
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Accounts.{User, UserNotifier, UserToken}
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

  @doc "Gets a single user scoped to an organization. Raises if not found."
  def get_user!(organization_id, id) do
    Repo.get_by!(User, id: id, organization_id: organization_id)
  end

  @doc "Lists an organization's staff, for the Team screen."
  def list_users(organization_id) do
    Repo.all(from u in User, where: u.organization_id == ^organization_id)
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
  `deliver_user_invite/3`. `organization_id` and `invited_by_id` are always
  explicit arguments, never taken from `attrs`, so an admin can only invite
  staff into their own organization; a given `site_id` is validated to
  belong to that same organization.
  """
  def invite_user(organization_id, invited_by_id, attrs) when is_integer(organization_id) do
    changeset =
      %User{}
      |> User.invite_changeset(attrs)
      |> Ecto.Changeset.put_change(:organization_id, organization_id)
      |> Ecto.Changeset.put_change(:invited_by_id, invited_by_id)
      |> validate_site_in_organization(organization_id)

    case Repo.insert(changeset) do
      {:ok, user} ->
        {encoded_token, user_token} = UserToken.build_email_token(user, "invite")
        Repo.insert!(user_token)
        {:ok, user, encoded_token}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp validate_site_in_organization(changeset, organization_id) do
    case Ecto.Changeset.get_change(changeset, :site_id) do
      nil ->
        changeset

      site_id ->
        query = from s in Site, where: s.id == ^site_id and s.organization_id == ^organization_id

        if Repo.exists?(query) do
          changeset
        else
          Ecto.Changeset.add_error(changeset, :site_id, "must belong to the same organization")
        end
    end
  end

  @doc """
  Emails the invite link to a newly-invited user. `invite_url_fun` receives
  the encoded token and must return the full invite URL.
  """
  def deliver_user_invite(%User{} = user, encoded_token, invite_url_fun)
      when is_function(invite_url_fun, 1) do
    UserNotifier.deliver_invite(user, invite_url_fun.(encoded_token))
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

  @doc "Gets the user for a given session token."
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc "Deletes the given session token."
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end
end
