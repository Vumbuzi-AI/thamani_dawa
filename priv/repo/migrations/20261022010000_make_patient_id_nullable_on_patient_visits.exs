defmodule ThamaniDawa.Repo.Migrations.MakePatientIdNullableOnPatientVisits do
  use Ecto.Migration

  def change do
    alter table(:patient_visits) do
      modify :patient_id, :integer, null: true
    end
  end
end
