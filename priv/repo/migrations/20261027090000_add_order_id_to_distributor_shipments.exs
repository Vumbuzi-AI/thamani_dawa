defmodule ThamaniDawa.Repo.Migrations.AddOrderIdToDistributorShipments do
  use Ecto.Migration

  def change do
    alter table(:distributor_shipments) do
      add :order_id, references(:distributor_orders, on_delete: :restrict)
    end

    create index(:distributor_shipments, [:order_id])
  end
end
