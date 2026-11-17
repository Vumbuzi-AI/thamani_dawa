defmodule ThamaniDawa.Repo.Migrations.CreateDistributorSerialisationBilling do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :serialisation_type, :string
      add :vat_registered, :boolean, null: false, default: true
      add :next_serial_invoice_number, :integer, null: false, default: 0
    end

    create table(:distributor_serial_usages) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :status, :string, null: false, default: "active"
      add :quantity_limit, :integer
      add :running_quantity, :integer, null: false, default: 0
      add :running_buffer, :integer, null: false, default: 0
      add :cycle_started_at, :utc_datetime, null: false
      add :billing_date, :utc_datetime
      add :closed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:distributor_serial_usages, [:organization_id])

    create unique_index(:distributor_serial_usages, [:organization_id],
             where: "status = 'active'",
             name: :distributor_serial_usages_one_active_index
           )

    create table(:distributor_serial_payments) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :serial_usage_id, references(:distributor_serial_usages, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :method, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :quantity, :integer, null: false
      add :buffer_quantity, :integer, null: false, default: 0
      add :unit_price, :decimal, null: false
      add :amount_excl_vat, :decimal, null: false
      add :vat_amount, :decimal, null: false
      add :amount, :decimal, null: false
      add :phone, :string
      add :provider_reference, :string
      add :manual_reference, :string
      add :failure_reason, :string
      add :paid_at, :utc_datetime
      add :invoice_number, :string
      add :initiated_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:distributor_serial_payments, [:organization_id, :inserted_at])
    create unique_index(:distributor_serial_payments, [:provider_reference])
    create unique_index(:distributor_serial_payments, [:organization_id, :invoice_number])
  end
end
