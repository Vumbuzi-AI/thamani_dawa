defmodule ThamaniDawa.Repo.Migrations.AddWarehouseManagementFieldsToBatches do
  use Ecto.Migration

  def change do
    alter table(:batches) do
      add :zone, :string, default: "receiving", null: false
      add :bin, :string
      add :status, :string, default: "active", null: false
      add :reserved_for_shipment_id, references(:distributor_shipments, on_delete: :nilify_all)
    end

    create index(:batches, [:reserved_for_shipment_id])
    create index(:batches, [:zone])
    create index(:batches, [:status])
  end
end
