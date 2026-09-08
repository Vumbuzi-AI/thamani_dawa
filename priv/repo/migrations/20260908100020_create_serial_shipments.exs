defmodule ThamaniDawa.Repo.Migrations.CreateSerialShipments do
  use Ecto.Migration

  def change do
    create table(:serial_shipments) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :gs1_request_id, references(:gs1_requests, on_delete: :nilify_all)

      # "sscc" (logistics units) or "serialised" (Data Matrix trade items).
      add :type, :string, null: false
      add :status, :string, null: false, default: "draft"

      add :batch, :string
      add :production_date, :date
      add :expiry_date, :date

      add :order_number, :string
      add :customer_part_number, :string
      add :material_description, :text

      add :from_gln_id, :string
      add :to_gln_id, :string
      add :from_address, :text
      add :to_address, :text
      add :from_po_box, :string
      add :from_company_name, :string
      add :to_po_box, :string
      add :to_company_name, :string

      timestamps(type: :utc_datetime)
    end

    create index(:serial_shipments, [:organization_id, :inserted_at])
    create index(:serial_shipments, [:gs1_request_id])

    create table(:serial_shipment_lines) do
      add :shipment_id, references(:serial_shipments, on_delete: :delete_all), null: false
      add :gtin, :string, null: false
      add :cases, :integer, null: false, default: 0
      add :items_per_case, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:serial_shipment_lines, [:shipment_id])
  end
end
