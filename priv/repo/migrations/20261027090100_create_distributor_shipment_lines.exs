defmodule ThamaniDawa.Repo.Migrations.CreateDistributorShipmentLines do
  use Ecto.Migration

  def change do
    create table(:distributor_shipment_lines) do
      add :shipment_id, references(:distributor_shipments, on_delete: :delete_all), null: false
      add :product_id, references(:products, on_delete: :restrict), null: false
      add :batch_id, references(:batches, on_delete: :restrict), null: false
      add :quantity, :integer, null: false
      add :unit_price, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:distributor_shipment_lines, [:shipment_id])
  end
end
