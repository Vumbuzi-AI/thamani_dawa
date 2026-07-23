defmodule ThamaniDawa.Repo.Migrations.CreateUsersAuthTables do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :site_id, references(:sites, on_delete: :nilify_all)
      add :invited_by_id, references(:users, on_delete: :nilify_all)
      add :name, :string, null: false
      add :email, :string, null: false
      add :hashed_password, :string
      add :hashed_pin, :string
      add :role, :string, null: false
      add :is_active, :boolean, null: false, default: true
      add :last_logged_in_at, :utc_datetime
      add :last_logged_out_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:users, [:organization_id])
    create index(:users, [:site_id])
    create index(:users, [:invited_by_id])
    create unique_index(:users, [:email])

    create table(:users_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end
