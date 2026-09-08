defmodule ThamaniDawa.Repo.Migrations.CreateSerialUsageCycles do
  use Ecto.Migration

  def change do
    # A local, display-only mirror of the plan state GS1 owns. GS1 remains the
    # single enforcer of allowances (serialisation.md §6) — nothing in this app
    # may decrement these counters and treat the result as authoritative.
    create table(:serial_usage_cycles) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      add :gs1_usage_id, :integer
      add :payment_reference, :string
      # "prepay" or "postpay".
      add :type, :string, null: false

      add :quantity_limit, :integer, null: false, default: 0
      add :buffer_limit, :integer, null: false, default: 10_000_000
      add :running_quantity, :integer, null: false, default: 0
      add :running_buffer, :integer, null: false, default: 0

      add :next_billing_date, :date
      add :overdue, :boolean, null: false, default: false
      add :synced_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:serial_usage_cycles, [:organization_id, :inserted_at])

    create unique_index(:serial_usage_cycles, [:organization_id, :gs1_usage_id],
             where: "gs1_usage_id IS NOT NULL",
             name: :serial_usage_cycles_org_gs1_usage_id_index
           )
  end
end
