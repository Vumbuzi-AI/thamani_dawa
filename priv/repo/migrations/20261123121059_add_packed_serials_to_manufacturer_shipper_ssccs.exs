defmodule ThamaniDawa.Repo.Migrations.AddPackedSerialsToManufacturerShipperSsccs do
  use Ecto.Migration

  def change do
    alter table(:manufacturer_shipper_ssccs) do
      add :packed_serials, {:array, :string}, null: false, default: []
    end

    create index(:manufacturer_shipper_ssccs, [:organization_id, :gtin, :batch])
  end
end
