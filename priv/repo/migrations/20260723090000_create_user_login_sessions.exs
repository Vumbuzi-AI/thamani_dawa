defmodule ThamaniDawa.Repo.Migrations.CreateUserLoginSessions do
  use Ecto.Migration

  def change do
    create table(:user_login_sessions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :logged_in_at, :utc_datetime, null: false
      add :logged_out_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:user_login_sessions, [:user_id])
    create index(:user_login_sessions, [:logged_in_at])
  end
end
