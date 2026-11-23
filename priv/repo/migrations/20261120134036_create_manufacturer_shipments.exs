defmodule ThamaniDawa.Repo.Migrations.CreateManufacturerShipments do
  use Ecto.Migration

  def change do
    create table(:manufacturer_shipments) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :created_by_id, references(:users, on_delete: :nilify_all)
      add :shipped_by_id, references(:users, on_delete: :nilify_all)
      add :reference, :string, null: false
      add :order_number, :string, null: false
      add :status, :string, null: false, default: "draft"
      add :origin_gln, :string, null: false
      add :origin_company, :string, null: false
      add :origin_address, :string
      add :destination_gln, :string, null: false
      add :destination_company, :string, null: false
      add :destination_address, :string
      add :shipped_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:manufacturer_shipments, [:organization_id, :reference])
    create index(:manufacturer_shipments, [:organization_id, :status])

    create table(:manufacturer_shipment_items) do
      add :manufacturer_shipment_id,
          references(:manufacturer_shipments, on_delete: :delete_all),
          null: false

      add :manufacturer_shipper_sscc_id,
          references(:manufacturer_shipper_ssccs, on_delete: :restrict),
          null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:manufacturer_shipment_items, [:manufacturer_shipper_sscc_id])

    create unique_index(:manufacturer_shipment_items, [
             :manufacturer_shipment_id,
             :manufacturer_shipper_sscc_id
           ])
  end
end
