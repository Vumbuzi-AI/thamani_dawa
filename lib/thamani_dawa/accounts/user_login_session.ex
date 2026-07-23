defmodule ThamaniDawa.Accounts.UserLoginSession do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_login_sessions" do
    field :logged_in_at, :utc_datetime
    field :logged_out_at, :utc_datetime

    belongs_to :user, ThamaniDawa.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(session, attrs) do
    session
    |> cast(attrs, [:user_id, :logged_in_at, :logged_out_at])
    |> validate_required([:user_id, :logged_in_at])
    |> foreign_key_constraint(:user_id)
  end
end
