defmodule ThamaniDawa.Repo.Migrations.CreateDispensedItems do
  use Ecto.Migration

  def change do
    create table(:dispensed_items) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      add :prescription_item_id, references(:prescription_items, on_delete: :delete_all),
        null: false

      add :batch_id, references(:batches, on_delete: :delete_all), null: false
      add :quantity, :integer, null: false
      add :unit_price, :decimal
      add :pharmacist_id, references(:users, on_delete: :nilify_all)
      add :is_verified, :boolean, null: false, default: false
      add :dispensed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:dispensed_items, [:organization_id])
    create index(:dispensed_items, [:prescription_item_id])
    create index(:dispensed_items, [:batch_id])
    create index(:dispensed_items, [:pharmacist_id])
  end
end
