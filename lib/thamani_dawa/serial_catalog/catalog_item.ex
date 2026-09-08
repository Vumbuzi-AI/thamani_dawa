defmodule ThamaniDawa.SerialCatalog.CatalogItem do
  @moduledoc """
  A GTIN in an organization's serialisation working catalog.

  Mirrors what `gs1_admin` calls `serial_barcodes`: a distributor serialises
  products it does not own, so the catalog is not the same set as
  `ThamaniDawa.Products`. `source` records where the row came from — `:local`
  for a GTIN the organization owns, `:external` for one pulled from GS1.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @sources ~w(local external)a

  schema "serial_catalog_items" do
    field :gtin, :string
    field :name, :string
    field :description, :string
    field :weight, :string
    field :uom, :string
    field :classification, :string
    field :target_market, :string
    field :comp_name, :string
    field :image, :string
    field :source, Ecto.Enum, values: @sources, default: :external

    belongs_to :organization, ThamaniDawa.Organizations.Organization

    timestamps(type: :utc_datetime)
  end

  @doc "The sources a catalog item can have."
  def sources, do: @sources

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :gtin,
      :name,
      :description,
      :weight,
      :uom,
      :classification,
      :target_market,
      :comp_name,
      :image,
      :source
    ])
    |> validate_required([:gtin])
    |> ThamaniDawa.Gtin.validate_gtin()
    |> unique_constraint(:gtin, name: :serial_catalog_items_organization_id_gtin_index)
  end
end
