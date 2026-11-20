defmodule ThamaniDawa.Repo.Migrations.AddShipmentLinkToCustomerReturns do
  use Ecto.Migration

  def change do
    alter table(:customer_returns) do
      add :shipment_id, references(:distributor_shipments, on_delete: :nilify_all)
      add :document_reference, :string
    end

    create index(:customer_returns, [:shipment_id])

    alter table(:customer_return_items) do
      add :serial, :string
      add :shipment_item_id, references(:distributor_shipment_items, on_delete: :nilify_all)
      add :matched, :boolean, null: false, default: false
    end

    create unique_index(:customer_return_items, [:shipment_item_id],
             where: "shipment_item_id IS NOT NULL",
             name: :customer_return_items_shipment_item_id_index
           )
  end
end
