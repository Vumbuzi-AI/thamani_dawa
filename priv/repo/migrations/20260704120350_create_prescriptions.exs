defmodule ThamaniDawa.Repo.Migrations.CreatePrescriptions do
  use Ecto.Migration

  def change do
    create table(:prescriptions) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :patient_id, references(:patients, on_delete: :delete_all), null: false
      add :prescriber_name, :string
      add :prescriber_reg_no, :string
      add :entered_by_id, references(:users, on_delete: :nilify_all)
      add :payment_type, :string
      add :has_paid, :boolean, null: false, default: false
      add :total_amount, :decimal
      add :status, :string, null: false, default: "pending"
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:prescriptions, [:organization_id])
    create index(:prescriptions, [:site_id])
    create index(:prescriptions, [:patient_id])
    create index(:prescriptions, [:entered_by_id])
  end
end
