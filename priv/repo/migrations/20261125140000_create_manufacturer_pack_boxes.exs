defmodule ThamaniDawa.Repo.Migrations.CreateManufacturerPackBoxes do
  use Ecto.Migration

  def change do
    alter table(:manufacturer_batches) do
      add_if_not_exists :from_gln, :string
      add_if_not_exists :from_name, :string
      add_if_not_exists :to_gln, :string
      add_if_not_exists :to_name, :string
    end

    create table(:manufacturer_pack_boxes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      add :mobile_user_id, references(:distributor_mobile_users, on_delete: :delete_all),
        null: false

      add :manufacturer_batch_id, references(:manufacturer_batches, on_delete: :delete_all),
        null: false

      add :manufacturer_shipper_sscc_id,
          references(:manufacturer_shipper_ssccs, on_delete: :nilify_all)

      add :status, :string, null: false, default: "draft"
      add :idempotency_key, :string
      add :from_gln, :string
      add :from_name, :string
      add :to_gln, :string
      add :to_name, :string

      timestamps(type: :utc_datetime)
    end

    create index(:manufacturer_pack_boxes, [:organization_id])
    create index(:manufacturer_pack_boxes, [:manufacturer_batch_id])

    create unique_index(:manufacturer_pack_boxes, [:mobile_user_id, :manufacturer_batch_id],
             where: "status = 'draft'",
             name: :manufacturer_pack_boxes_one_draft_per_user_batch
           )

    create unique_index(:manufacturer_pack_boxes, [:idempotency_key],
             where: "idempotency_key IS NOT NULL",
             name: :manufacturer_pack_boxes_idempotency_key_index
           )

    create table(:manufacturer_pack_box_scans) do
      add :box_id,
          references(:manufacturer_pack_boxes, type: :binary_id, on_delete: :delete_all),
          null: false

      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      add :manufacturer_product_id, references(:manufacturer_products, on_delete: :delete_all),
        null: false

      add :serial, :string, null: false
      add :claimed_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:manufacturer_pack_box_scans, [:box_id])

    create unique_index(
             :manufacturer_pack_box_scans,
             [:organization_id, :manufacturer_product_id, :serial],
             name: :manufacturer_pack_box_scans_claim_index
           )
  end
end
