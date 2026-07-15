defmodule ThamaniDawa.Repo.Migrations.DropNotNullPatientIdFromLabOrders do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE lab_orders ALTER COLUMN patient_id DROP NOT NULL"
  end

  def down do
    execute "ALTER TABLE lab_orders ALTER COLUMN patient_id SET NOT NULL"
  end
end
