defmodule ThamaniDawa.Repo.Migrations.CreateDistributorOrders do
  use Ecto.Migration

  def change do
    create table(:distributor_orders) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :customer_id, references(:distributor_customers, on_delete: :restrict), null: false
      add :status, :string, null: false, default: "pending"
      add :ordered_at, :utc_datetime, null: false
      add :delivery_address, :string

      timestamps(type: :utc_datetime)
    end

    create index(:distributor_orders, [:organization_id, :ordered_at])
    create index(:distributor_orders, [:customer_id])

    create table(:distributor_order_items) do
      add :order_id, references(:distributor_orders, on_delete: :delete_all), null: false
      add :product_id, references(:products, on_delete: :restrict), null: false
      add :quantity, :integer, null: false
      add :unit_price, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:distributor_order_items, [:order_id])
    create index(:distributor_order_items, [:product_id])
  end
end
