defmodule ThamaniDawa.ApiIdempotency do
  @moduledoc """
  Stores the successful response for one `Idempotency-Key` per user.

  The same key and the same body return the original response. The same key
  with a different body is a conflict. A failed attempt is not stored, so
  the client can correct the body or retry the same body after a validation
  error. Stock and payment writes run inside this transaction, so a crash
  before the key is saved does not leave a half-applied sale.
  """

  use Ecto.Schema
  import Ecto.Query

  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.Repo

  schema "api_idempotency_keys" do
    field :key, :string
    field :body_hash, :binary
    field :status, :integer
    field :body, :map

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def execute(user_id, key, params, fun)
      when is_integer(user_id) and is_binary(key) and is_function(fun, 0) do
    hash = :crypto.hash(:sha256, :erlang.term_to_binary(params))

    case Repo.transaction(fn -> run_locked(user_id, key, hash, fun) end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_locked(user_id, key, hash, fun) do
    case lock_key(user_id, key) do
      nil -> apply_and_store(user_id, key, hash, fun)
      %__MODULE__{} = existing -> replay(existing, hash)
    end
  end

  defp apply_and_store(user_id, key, hash, fun) do
    case fun.() do
      {:ok, status, body} when is_integer(status) and is_map(body) ->
        store!(user_id, key, hash, status, body)
        {:ok, status, stringify_keys(body)}

      {:error, reason} ->
        Repo.rollback(reason)

      other ->
        Repo.rollback(other)
    end
  end

  defp replay(%__MODULE__{body_hash: hash, status: status, body: body}, hash) do
    {:ok, status, body}
  end

  defp replay(%__MODULE__{}, _hash) do
    Repo.rollback(:idempotency_conflict)
  end

  defp lock_key(user_id, key) do
    Repo.one(
      from k in __MODULE__,
        where: k.user_id == ^user_id and k.key == ^key,
        lock: "FOR UPDATE"
    )
  end

  defp store!(user_id, key, hash, status, body) do
    %__MODULE__{}
    |> Ecto.Changeset.change(%{
      user_id: user_id,
      key: key,
      body_hash: hash,
      status: status,
      body: stringify_keys(body)
    })
    |> Ecto.Changeset.validate_required([:user_id, :key, :body_hash, :status, :body])
    |> Ecto.Changeset.unique_constraint([:user_id, :key])
    |> Repo.insert!()
  end

  defp stringify_keys(value) when is_map(value) and not is_struct(value) do
    Map.new(value, fn {key, nested} -> {to_string(key), stringify_keys(nested)} end)
  end

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
