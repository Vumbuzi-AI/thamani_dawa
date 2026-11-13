defmodule ThamaniDawa.Distributor.LoginAttempt do
  @moduledoc """
  A failed mobile sign-in, keyed by scope (`username`, `organization`,
  `device`, `ip`) rather than by foreign key, used for rate limiting.
  """

  use Ecto.Schema

  schema "distributor_login_attempts" do
    field :scope, :string
    field :key, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
