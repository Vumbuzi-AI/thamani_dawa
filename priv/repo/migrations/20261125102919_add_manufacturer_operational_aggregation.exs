defmodule ThamaniDawa.Repo.Migrations.AddManufacturerOperationalAggregation do
  use Ecto.Migration

  def change do
    alter table(:manufacturer_batches) do
      add :status, :string, null: false, default: "prepared"
      add :pack_quantity, :integer
      add :packs_per_shipper, :integer
      add :expected_shipper_count, :integer
      add :shipper_preparation_method, :string
      add_if_not_exists :from_gln, :string
      add_if_not_exists :to_gln, :string
      add :to_company_name, :string
      add :to_address, :string
      add :order_number, :string
      add :aggregation_started_at, :utc_datetime
      add :completed_at, :utc_datetime
    end

    create index(:manufacturer_batches, [:organization_id, :manufacturer_product_id, :status])

    alter table(:manufacturer_shipper_ssccs) do
      add :status, :string, null: false, default: "available"
      add :allocated_at, :utc_datetime
      add :assigned_at, :utc_datetime
      add :label_prepared_at, :utc_datetime
      add :label_print_requested_at, :utc_datetime
      add :verified_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :trackiq_status, :string, null: false, default: "not_started"
    end

    alter table(:manufacturer_pallets) do
      add :status, :string, null: false, default: "draft"
      add :allocated_at, :utc_datetime
      add :label_prepared_at, :utc_datetime
      add :label_print_requested_at, :utc_datetime
      add :verified_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :trackiq_status, :string, null: false, default: "not_started"
    end

    create table(:manufacturer_generation_operations) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      add :manufacturer_product_id, references(:manufacturer_products, on_delete: :restrict),
        null: false

      add :manufacturer_batch_id, references(:manufacturer_batches, on_delete: :restrict),
        null: false

      add :operation_key, :uuid, null: false
      add :serial_quantity, :integer, null: false
      add :sscc_quantity, :integer, null: false, default: 0
      add :status, :string, null: false, default: "pending"
      add :serial_allocation_status, :string, null: false, default: "pending"
      add :sscc_allocation_status, :string, null: false, default: "pending"
      add :serial_request_payload, :map
      add :serial_response, :map
      add :reconciliation_note, :string
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:manufacturer_generation_operations, [:operation_key])
    create index(:manufacturer_generation_operations, [:manufacturer_batch_id, :status])

    create table(:manufacturer_aggregation_sessions) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :manufacturer_batch_id, references(:manufacturer_batches, on_delete: :restrict)

      add :manufacturer_shipper_sscc_id,
          references(:manufacturer_shipper_ssccs, on_delete: :restrict)

      add :manufacturer_pallet_id, references(:manufacturer_pallets, on_delete: :restrict)
      add :created_by_id, references(:users, on_delete: :nilify_all)
      add :session_type, :string, null: false
      add :status, :string, null: false, default: "draft"
      add :preparation_method, :string
      add :expected_item_count, :integer
      add :finished_loading_at, :utc_datetime
      add :parent_verified_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :lock_version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime)
    end

    create index(:manufacturer_aggregation_sessions, [:organization_id, :session_type, :status])
    create index(:manufacturer_aggregation_sessions, [:manufacturer_batch_id])

    create unique_index(:manufacturer_aggregation_sessions, [:manufacturer_shipper_sscc_id],
             where: "manufacturer_shipper_sscc_id IS NOT NULL AND status != 'cancelled'",
             name: :manufacturer_aggregation_sessions_shipper_once
           )

    create table(:manufacturer_aggregation_session_items) do
      add :manufacturer_aggregation_session_id,
          references(:manufacturer_aggregation_sessions, on_delete: :delete_all),
          null: false

      add :manufacturer_serial_id, references(:manufacturer_serials, on_delete: :restrict)

      add :manufacturer_shipper_sscc_id,
          references(:manufacturer_shipper_ssccs, on_delete: :restrict)

      add :raw_identifier, :string, null: false
      add :captured_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(
             :manufacturer_aggregation_session_items,
             [:manufacturer_aggregation_session_id, :manufacturer_serial_id],
             where: "manufacturer_serial_id IS NOT NULL",
             name: :manufacturer_aggregation_session_items_serial_once_per_session
           )

    create unique_index(
             :manufacturer_aggregation_session_items,
             [:manufacturer_aggregation_session_id, :manufacturer_shipper_sscc_id],
             where: "manufacturer_shipper_sscc_id IS NOT NULL",
             name: :manufacturer_aggregation_session_items_shipper_once_per_session
           )

    create unique_index(:manufacturer_aggregation_session_items, [:manufacturer_serial_id],
             where: "manufacturer_serial_id IS NOT NULL",
             name: :manufacturer_serials_one_aggregation_session
           )

    create unique_index(:manufacturer_aggregation_session_items, [:manufacturer_shipper_sscc_id],
             where: "manufacturer_shipper_sscc_id IS NOT NULL",
             name: :manufacturer_shippers_one_pallet_session
           )
  end
end
