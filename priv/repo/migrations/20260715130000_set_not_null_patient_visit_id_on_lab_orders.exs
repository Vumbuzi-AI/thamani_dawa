defmodule ThamaniDawa.Repo.Migrations.SetNotNullPatientVisitIdOnLabOrders do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE lab_orders ALTER COLUMN patient_visit_id SET NOT NULL"
  end

  def down do
    execute "ALTER TABLE lab_orders ALTER COLUMN patient_visit_id DROP NOT NULL"
  end
end
