defmodule ThamaniDawa.Manufacturing.ShipperSscc do
  use Ecto.Schema
  import Ecto.Changeset

  schema "manufacturer_shipper_ssccs" do
    field :code, :string
    field :from_gln, :string
    field :from_company_name, :string
    field :from_address, :string
    field :to_gln, :string
    field :to_company_name, :string
    field :to_address, :string
    field :gtin, :string
    field :batch, :string
    field :production_date, :date
    field :expiry_date, :date
    field :count_of_trade_items, :integer
    field :packed_serials, {:array, :string}, default: []

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :pallet, ThamaniDawa.Manufacturing.Pallet, foreign_key: :manufacturer_pallet_id

    has_many :serials, ThamaniDawa.Manufacturing.Serial,
      foreign_key: :manufacturer_shipper_sscc_id

    has_many :sscc_batches, ThamaniDawa.Manufacturing.SsccBatch,
      foreign_key: :manufacturer_shipper_sscc_id

    has_many :batches, through: [:sscc_batches, :batch]

    timestamps(type: :utc_datetime)
  end

  @fields [
    :code,
    :from_gln,
    :from_company_name,
    :from_address,
    :to_gln,
    :to_company_name,
    :to_address,
    :gtin,
    :batch,
    :production_date,
    :expiry_date,
    :count_of_trade_items,
    :packed_serials,
    :manufacturer_pallet_id
  ]

  @doc false
  def changeset(shipper_sscc, attrs) do
    shipper_sscc
    |> cast(attrs, @fields)
    |> update_change(:code, fn
      value when is_binary(value) -> String.trim(value)
      value -> value
    end)
    |> validate_required([:code])
    |> unique_constraint(:code)
  end
end
