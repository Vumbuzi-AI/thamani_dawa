defmodule ThamaniDawa.Repo.Migrations.CreatePrescriptionBatchDispenses do
  use Ecto.Migration

  def change do
    create table(:prescription_batch_dispenses) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      add :prescription_item_id, references(:prescription_items, on_delete: :restrict),
        null: false

      add :batch_id, references(:batches, on_delete: :restrict), null: false
      add :quantity, :integer, null: false
      add :dispensed_by_id, references(:users, on_delete: :nilify_all)
      add :dispensed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:prescription_batch_dispenses, [:organization_id])
    create index(:prescription_batch_dispenses, [:prescription_item_id])
    create index(:prescription_batch_dispenses, [:batch_id])
  end
end
