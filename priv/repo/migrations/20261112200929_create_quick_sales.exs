defmodule ThamaniDawa.Repo.Migrations.CreateQuickSales do
  use Ecto.Migration

  def change do
    create table(:sales) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :site_id, references(:sites, on_delete: :restrict), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :total_amount, :decimal, null: false
      add :has_paid, :boolean, null: false, default: false
      add :status, :string, null: false, default: "completed"

      timestamps(type: :utc_datetime)
    end

    create index(:sales, [:organization_id])
    create index(:sales, [:site_id])
    create index(:sales, [:user_id])

    create table(:sale_items) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :sale_id, references(:sales, on_delete: :restrict), null: false
      add :product_id, references(:products, on_delete: :restrict), null: false
      add :quantity, :integer, null: false
      add :unit_price, :decimal, null: false
      add :is_verified, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:sale_items, [:organization_id])
    create index(:sale_items, [:sale_id])
    create index(:sale_items, [:product_id])

    create table(:sale_batch_dispenses) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :sale_item_id, references(:sale_items, on_delete: :restrict), null: false
      add :batch_id, references(:batches, on_delete: :restrict), null: false
      add :quantity, :integer, null: false
      add :dispensed_by_id, references(:users, on_delete: :nilify_all)
      add :dispensed_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:sale_batch_dispenses, [:organization_id])
    create index(:sale_batch_dispenses, [:sale_item_id])
    create index(:sale_batch_dispenses, [:batch_id])

    alter table(:payments) do
      add :sale_id, references(:sales, on_delete: :restrict)
    end

    create index(:payments, [:sale_id])

    create unique_index(:payments, [:sale_id],
             where: "status = 'completed' AND sale_id IS NOT NULL",
             name: :payments_one_completed_per_sale_index
           )
  end
end
