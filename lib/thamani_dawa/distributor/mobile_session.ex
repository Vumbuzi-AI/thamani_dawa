defmodule ThamaniDawa.Distributor.MobileSession do
  @moduledoc """
  A mobile app bearer-token pair. Only SHA-256 hashes of the access and
  refresh tokens are stored; the plaintext tokens exist only in the response
  that issued them.
  """

  use Ecto.Schema

  schema "distributor_mobile_sessions" do
    field :access_token_hash, :binary, redact: true
    field :refresh_token_hash, :binary, redact: true
    field :access_expires_at, :utc_datetime
    field :refresh_expires_at, :utc_datetime
    field :device_id, :string
    field :ip, :string

    belongs_to :mobile_user, ThamaniDawa.Distributor.MobileUser

    timestamps(type: :utc_datetime)
  end
end
