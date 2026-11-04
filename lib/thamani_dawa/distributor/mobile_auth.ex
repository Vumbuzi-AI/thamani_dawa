defmodule ThamaniDawa.Distributor.MobileAuth do
  @moduledoc """
  Sign-in and bearer-token sessions for distributor mobile app users.

    * Username + 4-digit PIN, verified with constant-time bcrypt. An unknown
      username still burns a `Bcrypt.no_user_verify/0`, so it is
      indistinguishable from a wrong PIN by timing.
    * Failed attempts are rate limited per username, organization, device
      and IP (`LoginAttempt` rows in a rolling 15-minute window), and five
      consecutive failures lock the account for 15 minutes.
    * A successful sign-in issues an access token (1 hour) and a refresh
      token (30 days). Both are random 32-byte URL-safe tokens; only their
      SHA-256 hashes are stored. Refreshing rotates both, so the old pair
      stops working immediately.
    * Every sign-in, refresh and authenticated request re-checks
      `account_active?/1`: the mobile user must be active, and its
      organization must be active and still operate as a distributor.
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.Distributor.{LoginAttempt, MobileSession, MobileUser}
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Repo

  @access_ttl_seconds 60 * 60
  @refresh_ttl_seconds 30 * 24 * 60 * 60
  @window_seconds 15 * 60
  @lock_seconds 15 * 60
  @max_failed_attempts 5
  @rate_limits %{"username" => 10, "organization" => 10, "device" => 30, "ip" => 50}

  @type tokens :: %{
          mobile_user: MobileUser.t(),
          access_token: String.t(),
          refresh_token: String.t(),
          access_expires_at: DateTime.t(),
          refresh_expires_at: DateTime.t()
        }

  @doc """
  Signs a mobile user in. `meta` may carry `:device_id` and `:ip` for rate
  limiting and session bookkeeping.
  """
  @spec login(String.t(), String.t(), map()) ::
          {:ok, tokens()} | {:error, :invalid_credentials | :locked | :rate_limited | :inactive}
  def login(username, pin, meta \\ %{}) do
    username = MobileUser.normalize_username(username || "")
    mobile_user = Repo.get_by(MobileUser, username: username)

    with :ok <- check_rate_limits(username, mobile_user, meta),
         :ok <- check_lock(mobile_user),
         :ok <- verify_pin(mobile_user, pin, username, meta),
         :ok <- check_active(mobile_user) do
      mobile_user =
        mobile_user
        |> Ecto.Changeset.change(
          failed_attempts: 0,
          locked_until: nil,
          last_login_at: now()
        )
        |> Repo.update!()

      issue_tokens(mobile_user, meta)
    end
  end

  @doc "Rotates a session's token pair using its refresh token."
  @spec refresh(String.t()) :: {:ok, tokens()} | {:error, :invalid_token | :inactive}
  def refresh(refresh_token) when is_binary(refresh_token) do
    query =
      from s in MobileSession,
        where: s.refresh_token_hash == ^hash(refresh_token),
        where: s.refresh_expires_at > ^now(),
        preload: [:mobile_user]

    case Repo.one(query) do
      nil ->
        {:error, :invalid_token}

      session ->
        with :ok <- check_active(session.mobile_user) do
          Repo.delete!(session)
          issue_tokens(session.mobile_user, %{device_id: session.device_id, ip: session.ip})
        end
    end
  end

  def refresh(_refresh_token), do: {:error, :invalid_token}

  @doc "Ends the session identified by `access_token`."
  def logout(access_token) when is_binary(access_token) do
    Repo.delete_all(from s in MobileSession, where: s.access_token_hash == ^hash(access_token))
    :ok
  end

  @doc """
  Resolves a bearer access token to its active mobile user, preloaded with
  its organization.
  """
  @spec authenticate(String.t() | nil) :: {:ok, MobileUser.t()} | {:error, :invalid_token}
  def authenticate(access_token) when is_binary(access_token) do
    query =
      from s in MobileSession,
        where: s.access_token_hash == ^hash(access_token),
        where: s.access_expires_at > ^now(),
        preload: [mobile_user: :organization]

    with %MobileSession{mobile_user: mobile_user} <- Repo.one(query),
         true <- account_active?(mobile_user) do
      {:ok, mobile_user}
    else
      _ -> {:error, :invalid_token}
    end
  end

  def authenticate(_access_token), do: {:error, :invalid_token}

  @doc "Revokes every session for a mobile user, forcing a fresh sign-in everywhere."
  def revoke_sessions(%MobileUser{id: id}) do
    Repo.delete_all(from s in MobileSession, where: s.mobile_user_id == ^id)
    :ok
  end

  @doc """
  Whether a mobile user may use the app: the account is active and its
  organization is active and still operates as a distributor. Demoting an
  organization out of the distributor model immediately locks its mobile
  users out.
  """
  def account_active?(%MobileUser{active: true} = mobile_user) do
    %MobileUser{organization: organization} = Repo.preload(mobile_user, :organization)
    organization.is_active and Organization.distributor?(organization)
  end

  def account_active?(_mobile_user), do: false

  defp check_rate_limits(username, mobile_user, meta) do
    since = DateTime.add(now(), -@window_seconds, :second)

    exceeded? =
      username
      |> attempt_keys(mobile_user, meta)
      |> Enum.any?(fn {scope, key} ->
        Repo.aggregate(
          from(a in LoginAttempt,
            where: a.scope == ^scope and a.key == ^key and a.inserted_at > ^since
          ),
          :count,
          :id
        ) >= Map.fetch!(@rate_limits, scope)
      end)

    if exceeded?, do: {:error, :rate_limited}, else: :ok
  end

  defp attempt_keys(username, mobile_user, meta) do
    [
      {"username", username},
      {"organization", mobile_user && Integer.to_string(mobile_user.organization_id)},
      {"device", meta_value(meta, :device_id)},
      {"ip", meta_value(meta, :ip)}
    ]
    |> Enum.reject(fn {_scope, key} -> key in [nil, ""] end)
  end

  defp meta_value(meta, key), do: Map.get(meta, key) || Map.get(meta, Atom.to_string(key))

  defp check_lock(%MobileUser{locked_until: %DateTime{} = locked_until}) do
    if DateTime.compare(locked_until, now()) == :gt, do: {:error, :locked}, else: :ok
  end

  defp check_lock(_mobile_user), do: :ok

  defp verify_pin(nil, _pin, username, meta) do
    Bcrypt.no_user_verify()
    record_failure(nil, username, meta)
    {:error, :invalid_credentials}
  end

  defp verify_pin(%MobileUser{} = mobile_user, pin, username, meta) do
    if is_binary(pin) and Bcrypt.verify_pass(pin, mobile_user.pin_hash) do
      :ok
    else
      record_failure(mobile_user, username, meta)
      {:error, :invalid_credentials}
    end
  end

  defp record_failure(mobile_user, username, meta) do
    timestamp = now()

    entries =
      username
      |> attempt_keys(mobile_user, meta)
      |> Enum.map(fn {scope, key} -> %{scope: scope, key: key, inserted_at: timestamp} end)

    Repo.insert_all(LoginAttempt, entries)
    maybe_lock(mobile_user)
  end

  defp maybe_lock(nil), do: :ok

  defp maybe_lock(%MobileUser{} = mobile_user) do
    failed_attempts = mobile_user.failed_attempts + 1

    locked_until =
      if failed_attempts >= @max_failed_attempts,
        do: DateTime.add(now(), @lock_seconds, :second)

    mobile_user
    |> Ecto.Changeset.change(
      failed_attempts: if(locked_until, do: 0, else: failed_attempts),
      locked_until: locked_until
    )
    |> Repo.update!()

    :ok
  end

  defp check_active(mobile_user) do
    if account_active?(mobile_user), do: :ok, else: {:error, :inactive}
  end

  defp issue_tokens(mobile_user, meta) do
    access_token = random_token()
    refresh_token = random_token()
    access_expires_at = DateTime.add(now(), @access_ttl_seconds, :second)
    refresh_expires_at = DateTime.add(now(), @refresh_ttl_seconds, :second)

    Repo.insert!(%MobileSession{
      mobile_user_id: mobile_user.id,
      access_token_hash: hash(access_token),
      refresh_token_hash: hash(refresh_token),
      access_expires_at: access_expires_at,
      refresh_expires_at: refresh_expires_at,
      device_id: meta_value(meta, :device_id),
      ip: meta_value(meta, :ip)
    })

    {:ok,
     %{
       mobile_user: mobile_user,
       access_token: access_token,
       refresh_token: refresh_token,
       access_expires_at: access_expires_at,
       refresh_expires_at: refresh_expires_at
     }}
  end

  defp random_token, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp hash(token), do: :crypto.hash(:sha256, token)

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
