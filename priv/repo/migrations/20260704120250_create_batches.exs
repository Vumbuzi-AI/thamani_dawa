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
      add :manufacturer, :string
      add :manufacture_date, :date
      add :expiry_date, :date, null: false
      add :quantity, :integer, null: false
      add :remaining_quantity, :integer, null: false
      add :cost_per_unit, :decimal
      add :supplier_id, references(:suppliers, on_delete: :nilify_all)
      add :received_at, :utc_datetime
      add :is_approved, :boolean, null: false, default: false
      add :approver_id, references(:users, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:batches, [:organization_id])
    create index(:batches, [:product_id])
    create index(:batches, [:site_id])
    create index(:batches, [:supplier_id])
    create index(:batches, [:approver_id])
  end
end
