defmodule ThamaniDawa.Products.Product do
  use Ecto.Schema
  import Ecto.Changeset

  schema "products" do
    field :organization_id, :id
    field :generic_name, :string
    field :brand_name, :string
    field :category, :string
    field :uom, :string
    field :gtin, :string
    field :is_otc, :boolean, default: false
    field :is_dangerous_drug, :boolean, default: false
    field :reorder_level, :integer
    field :price, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(product, attrs) do
    product
    |> cast(attrs, [
      :generic_name,
      :brand_name,
      :category,
      :uom,
      :gtin,
      :is_otc,
      :is_dangerous_drug,
      :reorder_level,
      :price
    ])
    |> validate_required([:price])
    |> ThamaniDawa.Gtin.validate_gtin()
    |> unique_constraint(:gtin, name: :products_organization_id_gtin_index)
  end
end
