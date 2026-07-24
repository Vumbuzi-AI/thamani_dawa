defmodule ThamaniDawa.Repo.Migrations.CreateStockTakes do
  use Ecto.Migration

  def change do
    create table(:stock_takes) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "draft"
      add :notes, :text
      add :started_by_id, references(:users, on_delete: :restrict), null: false
      add :started_at, :utc_datetime, null: false
      add :completed_by_id, references(:users, on_delete: :nilify_all)
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:stock_takes, [:organization_id])
    create index(:stock_takes, [:site_id])
    create index(:stock_takes, [:status])
    create index(:stock_takes, [:started_by_id])
    create index(:stock_takes, [:completed_by_id])

    create unique_index(:stock_takes, [:organization_id, :site_id],
             where: "status = 'draft'",
             name: :stock_takes_one_draft_per_site_index
           )
  end
end
