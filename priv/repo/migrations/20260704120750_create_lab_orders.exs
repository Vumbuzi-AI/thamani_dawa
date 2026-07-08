defmodule ThamaniDawa.Repo.Migrations.CreateLabOrders do
  use Ecto.Migration

  def change do
    create table(:lab_orders) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :patient_id, references(:patients, on_delete: :delete_all), null: false

      add :patient_visit_id, references(:patient_visits, on_delete: :restrict), null: false

      add :prescriber_name, :string
      add :ordered_by_id, references(:users, on_delete: :nilify_all)
      add :urgency, :string
      add :payment_type, :string
      add :has_paid, :boolean, null: false, default: false
      add :total_amount, :decimal
      add :status, :string, null: false, default: "pending"
      add :lab_report, :text
      add :test_findings, :text
      add :lab_request, :text
      add :referring_facility, :text
      add :referring_doctor, :text
      add :referred_date, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:lab_orders, [:organization_id])
    create index(:lab_orders, [:site_id])
    create index(:lab_orders, [:patient_id])
    create index(:lab_orders, [:patient_visit_id])
    create index(:lab_orders, [:ordered_by_id])
  end
end
