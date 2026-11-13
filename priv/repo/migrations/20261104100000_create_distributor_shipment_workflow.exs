defmodule ThamaniDawa.Repo.Migrations.CreateDistributorShipmentWorkflow do
  use Ecto.Migration

  def change do
    create table(:distributor_mobile_users) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :username, :string, null: false
      add :email, :string, null: false
      add :phone, :string
      add :pin_hash, :string, null: false
      add :active, :boolean, null: false, default: true
      add :failed_attempts, :integer, null: false, default: 0
      add :locked_until, :utc_datetime
      add :last_login_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:distributor_mobile_users, [:username])
    create index(:distributor_mobile_users, [:organization_id])

    create table(:distributor_mobile_sessions) do
      add :mobile_user_id, references(:distributor_mobile_users, on_delete: :delete_all),
        null: false

      add :access_token_hash, :binary, null: false
      add :refresh_token_hash, :binary, null: false
      add :access_expires_at, :utc_datetime, null: false
      add :refresh_expires_at, :utc_datetime, null: false
      add :device_id, :string
      add :ip, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:distributor_mobile_sessions, [:access_token_hash])
    create unique_index(:distributor_mobile_sessions, [:refresh_token_hash])
    create index(:distributor_mobile_sessions, [:mobile_user_id])

    create table(:distributor_login_attempts) do
      add :scope, :string, null: false
      add :key, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:distributor_login_attempts, [:scope, :key, :inserted_at])

    create table(:distributor_shipments) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :reference, :string, null: false
      add :order_number, :string, null: false
      add :status, :string, null: false, default: "draft"

      add :origin_site_id, references(:sites, on_delete: :nilify_all)
      add :origin_gln, :string, null: false
      add :origin_company, :string
      add :origin_address, :string
      add :origin_po_box, :string

      add :destination_customer_id,
          references(:distributor_customers, on_delete: :nilify_all)

      add :destination_gln, :string, null: false
      add :destination_company, :string
      add :destination_address, :string
      add :destination_po_box, :string

      add :created_by_id, references(:users, on_delete: :nilify_all)

      add :assigned_mobile_user_id,
          references(:distributor_mobile_users, on_delete: :nilify_all)

      add :submitted_by_mobile_user_id,
          references(:distributor_mobile_users, on_delete: :nilify_all)

      add :submitted_at, :utc_datetime
      add :approved_at, :utc_datetime
      add :approved_by_id, references(:users, on_delete: :nilify_all)
      add :rejected_at, :utc_datetime
      add :rejected_by_id, references(:users, on_delete: :nilify_all)
      add :rejection_reason, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:distributor_shipments, [:organization_id, :reference])
    create index(:distributor_shipments, [:organization_id, :status])
    create index(:distributor_shipments, [:organization_id, :order_number])
    create index(:distributor_shipments, [:assigned_mobile_user_id])

    create table(:distributor_shippers) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :shipment_id, references(:distributor_shipments, on_delete: :delete_all), null: false
      add :sequence, :integer, null: false
      add :name, :string, null: false
      add :sscc, :string
      add :gtin, :string
      add :batch, :string
      add :production_date, :date
      add :expiry_date, :date
      add :product_name, :string
      add :unit_count, :integer
      add :sscc_assigned_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:distributor_shippers, [:shipment_id, :sequence])
    create unique_index(:distributor_shippers, [:sscc])

    create table(:distributor_shipment_items) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :shipment_id, references(:distributor_shipments, on_delete: :delete_all), null: false
      add :shipper_id, references(:distributor_shippers, on_delete: :delete_all), null: false
      add :raw_data_matrix, :text, null: false
      add :gtin, :string, null: false
      add :batch, :string
      add :serial, :string, null: false
      add :production_date, :date
      add :expiry_date, :date
      add :product_id, references(:products, on_delete: :nilify_all)
      add :batch_id, references(:batches, on_delete: :nilify_all)
      add :product_name, :string
      add :product_source, :string, null: false
      add :validation_status, :string, null: false

      add :scanned_by_mobile_user_id,
          references(:distributor_mobile_users, on_delete: :nilify_all)

      add :scanned_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:distributor_shipment_items, [:shipment_id, :gtin, :serial])
    create index(:distributor_shipment_items, [:shipper_id])
    create index(:distributor_shipment_items, [:organization_id, :gtin])

    create table(:distributor_serial_reservations) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :shipment_id, references(:distributor_shipments, on_delete: :delete_all), null: false
      add :barcode, :string, null: false
      add :serial, :string, null: false
      add :committed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:distributor_serial_reservations, [:barcode, :serial])
    create index(:distributor_serial_reservations, [:shipment_id])

    create table(:distributor_shipment_events) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :shipment_id, references(:distributor_shipments, on_delete: :delete_all), null: false
      add :event, :string, null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :mobile_user_id, references(:distributor_mobile_users, on_delete: :nilify_all)
      add :details, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:distributor_shipment_events, [:shipment_id, :inserted_at])
  end
end
