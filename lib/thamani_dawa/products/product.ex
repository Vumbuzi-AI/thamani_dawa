defmodule ThamaniDawa.Products.Product do
  use Ecto.Schema
  import Ecto.Changeset

  @product_types [:drug, :lab_consumable, :general_supply]

  schema "products" do
    field :organization_id, :id
    field :generic_name, :string
    field :brand_name, :string
    field :name, :string
    field :product_type, Ecto.Enum, values: @product_types
    field :category, :string
    field :uom, :string
    field :gtin, :string
    field :is_otc, :boolean, default: false
    field :is_dangerous_drug, :boolean, default: false
    field :reorder_level, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(product, attrs) do
    product
    |> cast(attrs, [
      :generic_name,
      :brand_name,
      :name,
      :product_type,
      :category,
      :uom,
      :gtin,
      :is_otc,
      :is_dangerous_drug,
      :reorder_level
    ])
    |> validate_required([:product_type])
    |> validate_name_for_type()
    |> ThamaniDawa.Gtin.validate_gtin()
    |> unique_constraint(:gtin, name: :products_organization_id_gtin_index)
  end

  # Per §4.1: `generic_name` identifies a drug, `name` identifies everything else.
  defp validate_name_for_type(changeset) do
    case get_field(changeset, :product_type) do
      :drug -> validate_required(changeset, [:generic_name])
      nil -> changeset
      _ -> validate_required(changeset, [:name])
    end
  end

  @doc "The valid product types, per §4.1 of project.md."
  def product_types, do: @product_types
end
