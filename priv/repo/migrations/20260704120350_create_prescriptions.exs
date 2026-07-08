defmodule ThamaniDawa.Repo.Migrations.CreatePrescriptions do
  use Ecto.Migration

  def change do
    create table(:prescriptions) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :patient_visit_id, references(:patient_visits, on_delete: :restrict), null: false
      add :payment_type, :string
      add :has_paid, :boolean, null: false, default: false
      add :total_amount, :decimal
      add :status, :string, null: false, default: "pending"
      add :notes, :text
      add :doctors_note, :text
      add :is_external, :boolean, null: false, default: false
      add :source_facility, :text
      add :referring_doctor, :text
      add :referral_date, :time

      timestamps(type: :utc_datetime)
    end

    create index(:prescriptions, [:organization_id])
    create index(:prescriptions, [:user_id])
    create index(:prescriptions, [:patient_visit_id])
  end
end
