defmodule ThamaniDawa.Repo.Migrations.CreateBatches do
  use Ecto.Migration

  def change do
    create table(:batches) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :product_id, references(:products, on_delete: :delete_all), null: false
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :gtin, :string, null: false
      add :batch_no, :string, null: false
      add :serial, :string
      add :manufacture_date, :date
      add :expiry, :date, null: false
      add :quantity, :integer, null: false
      add :remaining_quantity, :integer, null: false
      add :cost_per_unit, :decimal
      add :unit_price, :decimal
      add :supplier_id, references(:suppliers, on_delete: :nilify_all)
      add :source_batch_id, references(:batches, on_delete: :nilify_all)
      add :received_by_id, references(:users, on_delete: :nilify_all)
      add :received_at, :utc_datetime
      add :is_active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:batches, [:organization_id])
    create index(:batches, [:product_id])
    create index(:batches, [:site_id])
    create index(:batches, [:supplier_id])
    create index(:batches, [:source_batch_id])
  end
end
