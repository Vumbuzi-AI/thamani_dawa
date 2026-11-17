defmodule ThamaniDawa.Repo.Migrations.CreateDistributorShipmentLineItems do
  use Ecto.Migration

  def change do
    create table(:distributor_shipment_line_items) do
      add :shipment_id, references(:distributor_shipments, on_delete: :delete_all), null: false
      add :product_id, references(:products, on_delete: :nilify_all)
      add :quantity, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:distributor_shipment_line_items, [:shipment_id])
  end
end
