defmodule ThamaniDawa.Repo.Migrations.CreatePayments do
  use Ecto.Migration

  def change do
    create table(:payments) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :site_id, references(:sites, on_delete: :restrict), null: false

      add :prescription_id, references(:prescriptions, on_delete: :restrict)
      add :lab_order_id, references(:lab_orders, on_delete: :restrict)
      add :order_type, :string, null: false

      add :amount, :decimal, null: false
      add :payment_type, :string, null: false
      add :provider_reference, :string

      add :status, :string, null: false, default: "pending"
      add :failure_reason, :string
      add :paid_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:payments, [:organization_id])
    create index(:payments, [:site_id])
    create index(:payments, [:prescription_id])
    create index(:payments, [:lab_order_id])

    create unique_index(:payments, [:organization_id, :provider_reference],
             where: "provider_reference IS NOT NULL",
             name: :payments_org_provider_reference_index
           )
  end
end
