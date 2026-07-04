defmodule ThamaniDawa.Repo.Migrations.CreateQualityAssuranceCharts do
  use Ecto.Migration

  def change do
    create table(:quality_assurance_charts) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :chart_type, :string, null: false
      add :month, :integer, null: false
      add :year, :integer, null: false
      add :daily_entries, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:quality_assurance_charts, [:organization_id])
    create index(:quality_assurance_charts, [:site_id])
    create unique_index(:quality_assurance_charts, [:organization_id, :chart_type, :month, :year])
  end
end
