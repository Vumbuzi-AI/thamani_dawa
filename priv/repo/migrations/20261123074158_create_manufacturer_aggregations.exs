defmodule ThamaniDawa.Repo.Migrations.CreateManufacturerAggregations do
  use Ecto.Migration

  def change do
    create table(:manufacturer_aggregations) do
      add :reference, :string
      add :status, :string, null: false, default: "draft"

      add :manufacturer_shipper_sscc_id,
          references(:manufacturer_shipper_ssccs, on_delete: :nilify_all)

      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :created_by_id, references(:users, on_delete: :nilify_all)
      add :approved_by_id, references(:users, on_delete: :nilify_all)
      add :rejected_by_id, references(:users, on_delete: :nilify_all)

      add :submitted_at, :utc_datetime
      add :approved_at, :utc_datetime
      add :rejected_at, :utc_datetime
      add :rejection_reason, :string

      timestamps(type: :utc_datetime)
    end

    create index(:manufacturer_aggregations, [:organization_id, :status])
    create index(:manufacturer_aggregations, [:manufacturer_shipper_sscc_id])

    create table(:manufacturer_aggregation_items) do
      add :manufacturer_aggregation_id,
          references(:manufacturer_aggregations, on_delete: :delete_all),
          null: false

      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      add :manufacturer_serial_id,
          references(:manufacturer_serials, on_delete: :nilify_all)

      add :raw_data_matrix, :string
      add :serial, :string
      add :gtin, :string
      add :validation_status, :string
      add :scanned_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:manufacturer_aggregation_items, [
             :manufacturer_aggregation_id,
             :serial
           ])

    create index(:manufacturer_aggregation_items, [:manufacturer_serial_id])
    create index(:manufacturer_aggregation_items, [:organization_id])
  end
end
