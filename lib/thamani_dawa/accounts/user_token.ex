defmodule ThamaniDawa.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query

  @hash_algorithm :sha256
  @rand_size 32

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    belongs_to :user, ThamaniDawa.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Builds a token used for maintaining a user's session, tied to the given user.
  """
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %__MODULE__{token: token, context: "session", user_id: user.id}}
  end

  @doc """
  Returns the query to look up a user by a given session token, scoped to
  tokens still within the session validity window and an active user --
  deactivating a user must invalidate any session they're already holding,
  not just block future logins, so this is checked on every request that
  resolves `current_scope`, not only at login time.
  """
  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(^validity_in_days("session"), "day") and user.is_active,
        select: user

    {:ok, query}
  end

  @doc """
  Builds a token for an email-delivered context (`"invite"` or
  `"reset_password"`). Unlike the session token, this one is hashed before
  storage — like a password, it's sent externally, so we don't keep the
  plaintext in the database.
  """
  def build_email_token(user, context) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %__MODULE__{token: hashed_token, context: context, sent_to: user.email, user_id: user.id}}
  end

  @doc """
  Returns the query to look up a user by a given email-delivered token and
  context, scoped to that context's validity window. Returns `:error` if the
  token isn't validly-encoded base64.
  """
  def verify_email_token_query(encoded_token, context) do
    case Base.url_decode64(encoded_token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)
        days = validity_in_days(context)

        query =
          from token in by_token_and_context_query(hashed_token, context),
            join: user in assoc(token, :user),
            where: token.inserted_at > ago(^days, "day") and token.sent_to == user.email,
            select: user

        {:ok, query}

      :error ->
        :error
    end
  end

  defp validity_in_days("session"), do: config(:session_validity_in_days)
  defp validity_in_days("invite"), do: config(:invite_validity_in_days)
  defp validity_in_days("reset_password"), do: config(:reset_password_validity_in_days)

  defp config(key), do: Application.get_env(:thamani_dawa, __MODULE__)[key]

  def invite_validity_in_days, do: config(:invite_validity_in_days)

  @doc "Returns the query for a given token and context, e.g. for deletion."
  def by_token_and_context_query(token, context) do
    from __MODULE__, where: [token: ^token, context: ^context]
  end

  @doc "Returns the query for all of a user's tokens in a given context, e.g. for deletion."
  def by_user_and_context_query(user, context) do
    from t in __MODULE__, where: t.user_id == ^user.id and t.context == ^context
  end
end
