defmodule ThamaniDawa.Repo.Migrations.CreateLabSpecimens do
  use Ecto.Migration

  def change do
    create table(:lab_specimens) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      add :lab_order_result_id, references(:lab_order_results, on_delete: :delete_all),
        null: false

      add :specimen_number, :string, null: false
      add :specimen_type, :string, null: false
      add :status, :string, null: false, default: "pending_collection"
      add :collected_by_id, references(:users, on_delete: :nilify_all)
      add :collected_at, :utc_datetime
      add :received_by_id, references(:users, on_delete: :nilify_all)
      add :received_at, :utc_datetime
      add :rejected_by_id, references(:users, on_delete: :nilify_all)
      add :rejected_at, :utc_datetime
      add :rejection_reason, :string
      add :notes, :string

      timestamps(type: :utc_datetime)
    end

    create index(:lab_specimens, [:organization_id])
    create unique_index(:lab_specimens, [:lab_order_result_id])
    create unique_index(:lab_specimens, [:organization_id, :specimen_number])
    create index(:lab_specimens, [:collected_by_id])
    create index(:lab_specimens, [:received_by_id])
    create index(:lab_specimens, [:rejected_by_id])
  end
end
