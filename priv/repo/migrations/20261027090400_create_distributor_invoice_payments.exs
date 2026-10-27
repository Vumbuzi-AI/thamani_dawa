defmodule ThamaniDawa.Repo.Migrations.CreateDistributorInvoicePayments do
  use Ecto.Migration

  def change do
    create table(:distributor_invoice_payments) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :invoice_id, references(:distributor_invoices, on_delete: :restrict), null: false
      add :amount, :integer, null: false
      add :method, :string, null: false
      add :paid_at, :utc_datetime, null: false
      add :note, :string

      timestamps(type: :utc_datetime)
    end

    create index(:distributor_invoice_payments, [:invoice_id])
  end
end
