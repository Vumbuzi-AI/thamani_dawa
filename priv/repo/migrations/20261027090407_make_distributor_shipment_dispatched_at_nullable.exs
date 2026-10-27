defmodule ThamaniDawa.Repo.Migrations.MakeDistributorShipmentDispatchedAtNullable do
  use Ecto.Migration

  def change do
    alter table(:distributor_shipments) do
      modify :dispatched_at, :utc_datetime, null: true, from: {:utc_datetime, null: false}
    end
  end
end
