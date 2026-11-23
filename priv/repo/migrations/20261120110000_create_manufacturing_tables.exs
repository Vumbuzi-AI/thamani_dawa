defmodule ThamaniDawa.Repo.Migrations.CreateManufacturingTables do
  use Ecto.Migration

  def change do
    create table(:manufacturer_products) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :gtin, :string, null: false
      add :name, :string, null: false
      add :description, :string
      add :brand_owner, :string
      add :brand_owner_address, :string
      add :licence_key, :string
      add :licence_type, :string
      add :status, :string, null: false, default: "active"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:manufacturer_products, [:organization_id, :gtin])
    create index(:manufacturer_products, [:organization_id])

    create table(:manufacturer_batches) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      add :manufacturer_product_id, references(:manufacturer_products, on_delete: :delete_all),
        null: false

      add :batch_no, :string, null: false
      add :production_date, :date, null: false
      add :expiry_date, :date, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:manufacturer_batches, [:manufacturer_product_id, :batch_no])
    create index(:manufacturer_batches, [:organization_id])

    create table(:manufacturer_pallets) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :code, :string, null: false
      add :from_gln, :string
      add :from_company_name, :string
      add :from_address, :string
      add :to_gln, :string
      add :to_company_name, :string
      add :to_address, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:manufacturer_pallets, [:code])
    create index(:manufacturer_pallets, [:organization_id])

    create table(:manufacturer_shipper_ssccs) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :manufacturer_pallet_id, references(:manufacturer_pallets, on_delete: :nilify_all)
      add :code, :string, null: false
      add :from_gln, :string
      add :from_company_name, :string
      add :from_address, :string
      add :to_gln, :string
      add :to_company_name, :string
      add :to_address, :string
      add :gtin, :string
      add :batch, :string
      add :production_date, :date
      add :expiry_date, :date
      add :count_of_trade_items, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:manufacturer_shipper_ssccs, [:code])
    create index(:manufacturer_shipper_ssccs, [:organization_id])
    create index(:manufacturer_shipper_ssccs, [:manufacturer_pallet_id])

    create table(:manufacturer_serials) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      add :manufacturer_product_id, references(:manufacturer_products, on_delete: :delete_all),
        null: false

      add :manufacturer_batch_id, references(:manufacturer_batches, on_delete: :delete_all),
        null: false

      add :manufacturer_shipper_sscc_id,
          references(:manufacturer_shipper_ssccs, on_delete: :nilify_all)

      add :serial, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:manufacturer_serials, [:manufacturer_product_id, :serial])
    create index(:manufacturer_serials, [:organization_id])
    create index(:manufacturer_serials, [:manufacturer_batch_id])
    create index(:manufacturer_serials, [:manufacturer_shipper_sscc_id])

    create table(:manufacturer_sscc_batches) do
      add :manufacturer_shipper_sscc_id,
          references(:manufacturer_shipper_ssccs, on_delete: :delete_all),
          null: false

      add :manufacturer_batch_id, references(:manufacturer_batches, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:manufacturer_sscc_batches, [
             :manufacturer_shipper_sscc_id,
             :manufacturer_batch_id
           ])

    create index(:manufacturer_sscc_batches, [:manufacturer_batch_id])
  end
end
