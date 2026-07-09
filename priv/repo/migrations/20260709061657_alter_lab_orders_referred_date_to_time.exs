defmodule ThamaniDawa.Repo.Migrations.AlterLabOrdersReferredDateToTime do
  use Ecto.Migration

  def change do
    alter table(:lab_orders) do
      modify :referred_date, :time, from: :utc_datetime
    end
  end
end
