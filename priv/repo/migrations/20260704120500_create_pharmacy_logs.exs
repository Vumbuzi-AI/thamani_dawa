defmodule ThamaniDawa.Repo.Migrations.CreatePharmacyLogs do
  use Ecto.Migration

  def change do
    create table(:pharmacy_logs) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :log_type, :string, null: false
      add :month, :integer, null: false
      add :year, :integer, null: false
      add :daily_entries, :map, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:pharmacy_logs, [:organization_id])
    create index(:pharmacy_logs, [:site_id])
    create unique_index(:pharmacy_logs, [:organization_id, :log_type, :month, :year])
  end
end
