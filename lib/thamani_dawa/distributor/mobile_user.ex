defmodule ThamaniDawa.Distributor.MobileUser do
  @moduledoc """
  A mobile scanning-app account belonging to a distributor organization. Not
  a portal `User`: it signs in with a username and a 4-digit PIN that is only
  ever emailed, never shown, and stored only as a bcrypt hash.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "distributor_mobile_users" do
    field :name, :string
    field :username, :string
    field :email, :string
    field :phone, :string
    field :pin_hash, :string, redact: true
    field :active, :boolean, default: true
    field :failed_attempts, :integer, default: 0
    field :locked_until, :utc_datetime
    field :last_login_at, :utc_datetime

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    has_many :sessions, ThamaniDawa.Distributor.MobileSession

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for the details a portal administrator can edit."
  def changeset(mobile_user, attrs) do
    mobile_user
    |> cast(attrs, [:name, :username, :email, :phone])
    |> update_change(:name, &trim/1)
    |> update_change(:username, &normalize_username/1)
    |> update_change(:email, &trim/1)
    |> validate_required([:name, :username, :email])
    |> validate_length(:username, min: 3, max: 40)
    |> validate_format(:phone, ~r/^(?=.*\d)\+?[0-9 ()-]+$/,
      message:
        "Enter a phone number using digits, spaces, hyphens, parentheses, and an optional leading +"
    )
    |> validate_format(:username, ~r/^[a-z0-9._-]+$/,
      message: "may only contain lowercase letters, numbers, dots, dashes and underscores"
    )
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[a-zA-Z]{2,}$/,
      message: "Please enter a valid email"
    )
    |> unique_constraint(:username, message: "is already taken")
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value

  @doc "Sets a new PIN hash (the plaintext PIN is never persisted)."
  def pin_changeset(mobile_user, pin) when is_binary(pin) do
    change(mobile_user,
      pin_hash: Bcrypt.hash_pwd_salt(pin),
      failed_attempts: 0,
      locked_until: nil
    )
  end

  @doc "Generates a random 4-digit PIN."
  def generate_pin do
    0..9999
    |> Enum.random()
    |> Integer.to_string()
    |> String.pad_leading(4, "0")
  end

  @doc "Lowercases and trims a username so lookups are case-insensitive."
  def normalize_username(username) when is_binary(username),
    do: username |> String.trim() |> String.downcase()

  def normalize_username(username), do: username
end
