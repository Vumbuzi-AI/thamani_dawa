defmodule ThamaniDawa.Repo.Migrations.CreateSerialCatalogItems do
  use Ecto.Migration

  def change do
    create table(:serial_catalog_items) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      add :gtin, :string, null: false
      add :name, :string
      add :description, :text
      add :weight, :string
      add :uom, :string
      add :classification, :string
      add :target_market, :string
      add :comp_name, :string
      add :image, :string
      # "local" when the GTIN belongs to this organization, "external" when it
      # was pulled from GS1 for a distributor who doesn't own it.
      add :source, :string, null: false, default: "external"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:serial_catalog_items, [:organization_id, :gtin])
  end
end
