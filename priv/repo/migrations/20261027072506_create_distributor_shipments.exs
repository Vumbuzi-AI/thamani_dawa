defmodule ThamaniDawa.Repo.Migrations.CreateDistributorShipments do
  use Ecto.Migration

  def change do
    create table(:distributor_shipments) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :customer_id, references(:distributor_customers, on_delete: :restrict), null: false
      add :warehouse_id, references(:sites, on_delete: :restrict), null: false
      add :destination, :string, null: false
      add :status, :string, null: false, default: "dispatched"
      add :dispatched_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:distributor_shipments, [:organization_id])
    create index(:distributor_shipments, [:customer_id])
    create index(:distributor_shipments, [:warehouse_id])
  end
end
