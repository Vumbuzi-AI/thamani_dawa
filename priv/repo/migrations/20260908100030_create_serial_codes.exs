defmodule ThamaniDawa.Repo.Migrations.CreateSerialCodes do
  use Ecto.Migration

  def change do
    create table(:serial_ssccs) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :shipment_id, references(:serial_shipments, on_delete: :delete_all), null: false
      add :parent_sscc_id, references(:serial_ssccs, on_delete: :nilify_all)

      add :code, :string, null: false
      # "pallet" (extension digit 1) or "case" (extension digit 2), per §2.4.3.
      add :level, :string, null: false
      # Which extension digit GS1 actually used, echoed back so local records
      # stay faithful to the issuing system (§8.6).
      add :extension_digit, :string
      add :image, :string
      add :issued_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:serial_ssccs, [:code])
    create index(:serial_ssccs, [:shipment_id])
    create index(:serial_ssccs, [:organization_id])

    # Contents of a logistics unit. More than one row here means a mixed
    # pallet, which still counts as exactly one billable serial (§2.4.4).
    create table(:serial_sscc_items) do
      add :sscc_id, references(:serial_ssccs, on_delete: :delete_all), null: false
      add :gtin, :string, null: false
      add :count, :integer, null: false, default: 0
      add :items, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:serial_sscc_items, [:sscc_id])

    create table(:serialised_codes) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :shipment_id, references(:serial_shipments, on_delete: :delete_all), null: false
      add :sscc_id, references(:serial_ssccs, on_delete: :nilify_all)

      add :gtin, :string, null: false
      add :serial, :string, null: false
      add :image, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:serialised_codes, [:organization_id, :serial])
    create index(:serialised_codes, [:organization_id, :gtin])
    create index(:serialised_codes, [:shipment_id])

    create table(:serialization_logs) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :shipment_id, references(:serial_shipments, on_delete: :nilify_all)

      add :type, :string, null: false
      add :gtin, :string
      add :batch, :string
      add :count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:serialization_logs, [:organization_id, :inserted_at])
  end
end
