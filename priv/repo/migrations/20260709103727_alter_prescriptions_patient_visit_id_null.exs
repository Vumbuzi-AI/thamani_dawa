defmodule ThamaniDawa.Repo.Migrations.AlterPrescriptionsPatientVisitIdNull do
  use Ecto.Migration

  def change do
    alter table(:prescriptions) do
      modify :patient_visit_id, :id, null: true
    end
  end
end
