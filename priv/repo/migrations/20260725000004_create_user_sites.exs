defmodule ThamaniDawa.Repo.Migrations.CreateUserSites do
  use Ecto.Migration

  def change do
    create table(:user_sites) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :site_id, references(:sites, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:user_sites, [:organization_id])
    create index(:user_sites, [:site_id])
    create unique_index(:user_sites, [:user_id, :site_id])
  end
end
