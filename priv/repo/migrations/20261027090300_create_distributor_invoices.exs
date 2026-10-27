defmodule ThamaniDawa.Repo.Migrations.CreateDistributorInvoices do
  use Ecto.Migration

  def change do
    create table(:distributor_invoices) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :order_id, references(:distributor_orders, on_delete: :restrict), null: false
      add :shipment_id, references(:distributor_shipments, on_delete: :restrict), null: false
      add :customer_id, references(:distributor_customers, on_delete: :restrict), null: false
      add :number, :integer, null: false
      add :issued_at, :utc_datetime, null: false
      add :subtotal, :integer, null: false
      add :total, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:distributor_invoices, [:order_id])
    create unique_index(:distributor_invoices, [:shipment_id])
    create unique_index(:distributor_invoices, [:organization_id, :number])
    create index(:distributor_invoices, [:organization_id])

    create table(:distributor_invoice_lines) do
      add :invoice_id, references(:distributor_invoices, on_delete: :delete_all), null: false
      add :product_id, references(:products, on_delete: :restrict), null: false
      add :quantity, :integer, null: false
      add :unit_price, :integer, null: false
      add :line_total, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:distributor_invoice_lines, [:invoice_id])
  end
end
