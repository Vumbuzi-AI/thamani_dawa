defmodule ThamaniDawa.Manufacturing.Pallet do
  use Ecto.Schema
  import Ecto.Changeset

  schema "manufacturer_pallets" do
    field :code, :string
    field :from_gln, :string
    field :from_company_name, :string
    field :from_address, :string
    field :to_gln, :string
    field :to_company_name, :string
    field :to_address, :string

    belongs_to :organization, ThamaniDawa.Organizations.Organization

    has_many :shipper_ssccs, ThamaniDawa.Manufacturing.ShipperSscc,
      foreign_key: :manufacturer_pallet_id

    timestamps(type: :utc_datetime)
  end

  @fields [
    :code,
    :from_gln,
    :from_company_name,
    :from_address,
    :to_gln,
    :to_company_name,
    :to_address
  ]

  @doc false
  def changeset(pallet, attrs) do
    pallet
    |> cast(attrs, @fields)
    |> update_change(:code, fn
      value when is_binary(value) -> String.trim(value)
      value -> value
    end)
    |> validate_required([:code])
    |> unique_constraint(:code)
  end
end
