defmodule ThamaniDawa.Repo.Migrations.AddParticipantTierToDistributorShipments do
  use Ecto.Migration

  def change do
    alter table(:distributor_shipments) do
      add :participant_tier, :string, null: false, default: "distributor"
    end

    create index(:distributor_shipments, [:organization_id, :participant_tier, :status])
  end
end
