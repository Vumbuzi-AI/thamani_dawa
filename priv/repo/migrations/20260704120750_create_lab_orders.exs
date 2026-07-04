defmodule ThamaniDawa.Repo.Migrations.CreateLabOrders do
  use Ecto.Migration

  def change do
    create table(:lab_orders) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :patient_id, references(:patients, on_delete: :delete_all), null: false
      add :prescriber_name, :string
      add :ordered_by_id, references(:users, on_delete: :nilify_all)
      add :urgency, :string
      add :payment_type, :string
      add :has_paid, :boolean, null: false, default: false
      add :total_amount, :decimal
      add :sample_collection_date, :date
      add :sample_collection_description, :string
      add :status, :string, null: false, default: "pending"
      add :lab_report, :text
      add :test_findings, :text

      timestamps(type: :utc_datetime)
    end

    create index(:lab_orders, [:organization_id])
    create index(:lab_orders, [:site_id])
    create index(:lab_orders, [:patient_id])
    create index(:lab_orders, [:ordered_by_id])
  end
end
