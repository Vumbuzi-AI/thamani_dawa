defmodule ThamaniDawa.Repo.Migrations.CreateSites do
  use Ecto.Migration

  def change do
    create table(:sites) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :site_type, :string, null: false
      add :gln, :string
      add :address, :string
      add :lat, :float
      add :long, :float
      add :is_active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:sites, [:organization_id])
    create unique_index(:sites, [:gln])
  end
end
