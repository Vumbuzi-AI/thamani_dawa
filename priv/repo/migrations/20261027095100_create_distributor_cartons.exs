defmodule ThamaniDawa.Repo.Migrations.CreateDistributorCartons do
  use Ecto.Migration

  def change do
    create table(:distributor_cartons) do
      add :sscc, :string, null: false
      add :sequence_in_shipment, :integer, null: false
      add :shipment_id, references(:distributor_shipments, on_delete: :restrict), null: false
      add :organization_id, references(:organizations, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:distributor_cartons, [:sscc])
    create index(:distributor_cartons, [:shipment_id])
    create index(:distributor_cartons, [:organization_id])
  end
end
