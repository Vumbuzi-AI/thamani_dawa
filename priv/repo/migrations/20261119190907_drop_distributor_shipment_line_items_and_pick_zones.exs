defmodule ThamaniDawa.Repo.Migrations.DropDistributorShipmentLineItemsAndPickZones do
  use Ecto.Migration

  def up do
    drop table(:distributor_shipment_line_items)

    execute("""
    UPDATE batches
    SET zone = 'storage', reserved_for_shipment_id = NULL
    WHERE zone IN ('picking', 'staging')
    """)

    drop_if_exists index(:batches, [:reserved_for_shipment_id])

    alter table(:batches) do
      remove :reserved_for_shipment_id
    end
  end

  def down do
    alter table(:batches) do
      add :reserved_for_shipment_id, references(:distributor_shipments, on_delete: :nilify_all)
    end

    create index(:batches, [:reserved_for_shipment_id])

    create table(:distributor_shipment_line_items) do
      add :shipment_id, references(:distributor_shipments, on_delete: :delete_all), null: false
      add :product_id, references(:products, on_delete: :nilify_all)
      add :quantity, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:distributor_shipment_line_items, [:shipment_id])
  end
end
