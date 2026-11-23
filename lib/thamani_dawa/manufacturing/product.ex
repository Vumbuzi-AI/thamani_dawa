defmodule ThamaniDawa.Manufacturing.Product do
  use Ecto.Schema
  import Ecto.Changeset

  schema "manufacturer_products" do
    field :gtin, :string
    field :name, :string
    field :description, :string
    field :brand_owner, :string
    field :brand_owner_address, :string
    field :licence_key, :string
    field :licence_type, :string
    field :status, :string, default: "active"

    belongs_to :organization, ThamaniDawa.Organizations.Organization

    has_many :batches, ThamaniDawa.Manufacturing.Batch, foreign_key: :manufacturer_product_id

    has_many :serials, ThamaniDawa.Manufacturing.Serial, foreign_key: :manufacturer_product_id

    timestamps(type: :utc_datetime)
  end

  @fields [
    :gtin,
    :name,
    :description,
    :brand_owner,
    :brand_owner_address,
    :licence_key,
    :licence_type,
    :status
  ]

  @doc false
  def changeset(product, attrs) do
    product
    |> cast(attrs, @fields)
    |> trim_change(:gtin)
    |> trim_change(:name)
    |> validate_required([:gtin, :name])
    |> validate_format(:gtin, ~r/^\d{8,14}$/, message: "must be 8 to 14 digits")
    |> unique_constraint([:organization_id, :gtin])
  end

  defp trim_change(changeset, field) do
    update_change(changeset, field, fn
      value when is_binary(value) -> String.trim(value)
      value -> value
    end)
  end
end
