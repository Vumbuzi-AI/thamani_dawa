defmodule ThamaniDawa.Products.Product do
  use Ecto.Schema
  import Ecto.Changeset

  schema "products" do
    field :generic_name, :string
    field :brand_name, :string
    field :category, :string
    field :uom, :string
    field :gtin, :string
    field :is_otc, :boolean, default: false
    field :is_dangerous_drug, :boolean, default: false
    field :reorder_level, :integer
    field :price, :integer
    field :is_active, :boolean, default: true

    belongs_to :organization, ThamaniDawa.Organizations.Organization

    has_many :batches, ThamaniDawa.Batches.Batch
    has_many :prescription_items, ThamaniDawa.Prescriptions.PrescriptionItem

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
      :price,
      :is_active
    ])
    |> validate_required([:price, :uom, :gtin])
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> validate_has_a_name()
    |> ThamaniDawa.Gtin.validate_gtin()
    |> unique_constraint(:gtin, name: :products_organization_id_gtin_index)
  end

  defp validate_has_a_name(changeset) do
    if blank?(get_field(changeset, :generic_name)) and blank?(get_field(changeset, :brand_name)) do
      add_error(changeset, :generic_name, "enter a generic or brand name")
    else
      changeset
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
