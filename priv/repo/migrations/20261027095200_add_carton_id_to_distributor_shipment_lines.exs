defmodule ThamaniDawa.Repo.Migrations.AddCartonIdToDistributorShipmentLines do
  use Ecto.Migration

  def change do
    alter table(:distributor_shipment_lines) do
      add :carton_id, references(:distributor_cartons, on_delete: :nilify_all)
    end

    create index(:distributor_shipment_lines, [:carton_id])
  end
end
