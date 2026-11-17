defmodule ThamaniDawa.Repo.Migrations.AddReturnsToShipmentsAndGoodsReceipts do
  use Ecto.Migration

  def change do
    alter table(:distributor_shipments) do
      add :is_return, :boolean, default: false, null: false
      add :reference_shipment_id, references(:distributor_shipments, on_delete: :nilify_all)
    end

    alter table(:goods_receipts) do
      add :is_return, :boolean, default: false, null: false
      add :reference_receipt_id, references(:goods_receipts, on_delete: :nilify_all)
    end

    create index(:distributor_shipments, [:reference_shipment_id])
    create index(:goods_receipts, [:reference_receipt_id])
  end
end
