defmodule ThamaniDawa.Repo.Migrations.CreateInventoryDisposalItems do
  use Ecto.Migration

  def change do
    create table(:inventory_disposal_items) do
      add :organization_id, references(:organizations, on_delete: :restrict), null: false

      add :inventory_disposal_id, references(:inventory_disposals, on_delete: :delete_all),
        null: false

      add :batch_id, references(:batches, on_delete: :restrict), null: false
      add :available_quantity, :integer, null: false
      add :quantity, :integer, null: false
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:inventory_disposal_items, [:organization_id])
    create index(:inventory_disposal_items, [:inventory_disposal_id])
    create unique_index(:inventory_disposal_items, [:inventory_disposal_id, :batch_id])
  end
end
