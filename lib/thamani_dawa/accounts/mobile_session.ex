defmodule ThamaniDawa.Accounts.MobileSession do
  @moduledoc """
  Bearer sessions for the phone app.

  Browser sessions stay in `users_tokens` context `"session"` and keep their
  30-minute idle timeout. These tokens use `"mobile_access"` and
  `"mobile_refresh"`, are stored hashed, and are revoked by deleting the
  pair. A phone login does not replace a browser login.
  """

  import Ecto.Query

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Accounts.{User, UserToken}
  alias ThamaniDawa.Repo

  @access_context "mobile_access"
  @refresh_context "mobile_refresh"
  @rand_size 32

  def log_in(email, password) when is_binary(email) and is_binary(password) do
    user = Accounts.get_user_by_email(String.trim(email))

    cond do
      match?(%User{}, user) and User.valid_password?(user, password) and inactive?(user) ->
        {:error, :account_inactive}

      match?(%User{}, user) and User.valid_password?(user, password) ->
        open_session(user)

      true ->
        {:error, :invalid_credentials}
    end
  end

  def log_in(_email, _password), do: {:error, :bad_request}

  def refresh(token) when is_binary(token) do
    case rotate(token) do
      {:ok, {tokens, user}} -> {:ok, tokens, user}
      {:error, reason} -> {:error, reason}
    end
  end

  def refresh(_token), do: {:error, :invalid_token}

  def verify_access(token) when is_binary(token) do
    case fetch_token(token, @access_context, access_hours(), "hour") do
      nil -> :error
      %{user: user} -> {:ok, preload(user)}
    end
  end

  def verify_access(_token), do: :error

  def revoke_access(token) when is_binary(token) do
    case fetch_token(token, @access_context, access_hours(), "hour") do
      nil ->
        :ok

      %{user: user, sent_to: pair} ->
        Repo.delete_all(pair_query(user.id, pair))
        Accounts.update_user_last_logged_out(user)
        Accounts.record_logout_session(user.id)
        :ok
    end
  end

  def revoke_access(_token), do: :ok

  def expires_in, do: access_hours() * 3600

  defp rotate(token) do
    Repo.transaction(fn ->
      case lock_token(token, @refresh_context, refresh_days(), "day") do
        nil ->
          Repo.rollback(:invalid_token)

        %{user: user, sent_to: pair} ->
          Repo.delete_all(pair_query(user.id, pair))
          {tokens, user} = insert_pair(user)
          {tokens, preload(user)}
      end
    end)
  end

  defp open_session(user) do
    Accounts.update_user_last_logged_in(user)
    Accounts.create_login_session(user.id)
    {tokens, user} = insert_pair(user)
    {:ok, tokens, preload(user)}
  end

  defp insert_pair(user) do
    pair = random_token()
    access = random_token()
    refresh = random_token()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%UserToken{
      token: hash(access),
      context: @access_context,
      sent_to: pair,
      user_id: user.id,
      last_used_at: now
    })

    Repo.insert!(%UserToken{
      token: hash(refresh),
      context: @refresh_context,
      sent_to: pair,
      user_id: user.id,
      last_used_at: now
    })

    {%{access_token: access, refresh_token: refresh, expires_in: expires_in()}, user}
  end

  defp inactive?(user) do
    not user.is_active or not organization_active?(user)
  end

  defp organization_active?(user) do
    user = Repo.preload(user, :organization)
    user.organization.is_active
  end

  defp preload(user) do
    Repo.preload(user, [:organization, :current_site, :sites], force: true)
  end

  defp fetch_token(encoded, context, amount, unit) do
    case hashed(encoded) do
      {:ok, hashed_token} -> Repo.one(token_query(hashed_token, context, amount, unit, false))
      :error -> nil
    end
  end

  defp lock_token(encoded, context, amount, unit) do
    case hashed(encoded) do
      {:ok, hashed_token} -> Repo.one(token_query(hashed_token, context, amount, unit, true))
      :error -> nil
    end
  end

  defp token_query(hashed_token, context, amount, unit, lock?) do
    query =
      from t in UserToken,
        join: u in assoc(t, :user),
        where: t.token == ^hashed_token and t.context == ^context and u.is_active == true,
        select: %{user: u, sent_to: t.sent_to}

    query =
      case unit do
        "hour" -> from t in query, where: t.inserted_at > ago(^amount, "hour")
        "day" -> from t in query, where: t.inserted_at > ago(^amount, "day")
      end

    if lock?, do: from(t in query, lock: "FOR UPDATE"), else: query
  end

  defp pair_query(user_id, pair) do
    from t in UserToken,
      where:
        t.user_id == ^user_id and t.sent_to == ^pair and
          t.context in [^@access_context, ^@refresh_context]
  end

  defp hash(encoded) do
    {:ok, hashed_token} = hashed(encoded)
    hashed_token
  end

  defp hashed(encoded) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, raw} -> {:ok, :crypto.hash(:sha256, raw)}
      :error -> :error
    end
  end

  defp random_token do
    @rand_size
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp access_hours do
    Application.get_env(:thamani_dawa, __MODULE__)[:access_token_hours] || 12
  end

  defp refresh_days do
    Application.get_env(:thamani_dawa, __MODULE__)[:refresh_token_days] || 90
  end
end
