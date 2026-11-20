defmodule ThamaniDawa.Products.Product do
  use Ecto.Schema
  import Ecto.Changeset

  schema "products" do
    field :generic_name, :string
    field :brand_name, :string
    field :strength, :string
    field :category, :string
    field :manufacturer, :string
    field :uom, :string
    field :pack_uom, :string
    field :units_per_pack, :integer
    field :net_content_quantity, :integer
    field :net_content_uom, :string
    field :gtin, :string
    field :inventory_type, Ecto.Enum, values: [:medicine, :lab_consumable], default: :medicine
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
      :strength,
      :category,
      :manufacturer,
      :uom,
      :pack_uom,
      :units_per_pack,
      :net_content_quantity,
      :net_content_uom,
      :gtin,
      :inventory_type,
      :is_otc,
      :is_dangerous_drug,
      :reorder_level,
      :price,
      :is_active
    ])
    |> update_change(:category, &normalize_category/1)
    |> update_change(:pack_uom, &normalize_pack_uom/1)
    |> update_change(:net_content_uom, &normalize_pack_uom/1)
    |> validate_required([:price, :uom, :gtin, :inventory_type])
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> validate_number(:units_per_pack, greater_than: 0)
    |> validate_number(:net_content_quantity, greater_than: 0)
    |> validate_packaging()
    |> validate_net_content()
    |> validate_has_a_name()
    |> ThamaniDawa.Gtin.validate_gtin()
    |> unique_constraint(:gtin, name: :products_organization_id_gtin_index)
  end

  @doc false
  def normalize_category(nil), do: nil

  def normalize_category(category) when is_binary(category) do
    category = category |> String.trim() |> String.replace(~r/\s+/, " ")
    if category == "", do: nil, else: String.capitalize(category)
  end

  @doc false
  def normalize_pack_uom(nil), do: nil

  def normalize_pack_uom(pack_uom) when is_binary(pack_uom) do
    case String.trim(pack_uom) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp validate_packaging(changeset) do
    pack_uom = get_field(changeset, :pack_uom)
    units_per_pack = get_field(changeset, :units_per_pack)

    cond do
      is_binary(pack_uom) and pack_uom != "" and is_nil(units_per_pack) ->
        add_error(changeset, :units_per_pack, "must be set when pack unit is specified")

      not is_nil(units_per_pack) and (is_nil(pack_uom) or pack_uom == "") ->
        add_error(changeset, :pack_uom, "must be set when units per pack is specified")

      true ->
        changeset
    end
  end

  defp validate_net_content(changeset) do
    quantity = get_field(changeset, :net_content_quantity)
    uom = get_field(changeset, :net_content_uom)

    cond do
      is_integer(quantity) and (is_nil(uom) or uom == "") ->
        add_error(changeset, :net_content_uom, "must be set when contents are specified")

      is_binary(uom) and uom != "" and is_nil(quantity) ->
        add_error(
          changeset,
          :net_content_quantity,
          "must be set when a contents unit is specified"
        )

      true ->
        changeset
    end
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
