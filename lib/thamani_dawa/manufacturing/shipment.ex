defmodule ThamaniDawa.Manufacturing.Shipment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "manufacturer_shipments" do
    field :reference, :string
    field :order_number, :string
    field :status, :string, default: "draft"
    field :origin_gln, :string
    field :origin_company, :string
    field :origin_address, :string
    field :destination_gln, :string
    field :destination_company, :string
    field :destination_address, :string
    field :shipped_at, :utc_datetime
    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :created_by, ThamaniDawa.Accounts.User
    belongs_to :shipped_by, ThamaniDawa.Accounts.User

    has_many :items, ThamaniDawa.Manufacturing.ShipmentItem,
      foreign_key: :manufacturer_shipment_id

    has_many :shipper_ssccs, through: [:items, :shipper_sscc]
    timestamps(type: :utc_datetime)
  end

  def changeset(shipment, attrs) do
    shipment
    |> cast(attrs, [:order_number, :origin_gln, :destination_gln])
    |> update_change(:order_number, &String.trim/1)
    |> update_change(:origin_gln, &String.trim/1)
    |> update_change(:destination_gln, &String.trim/1)
    |> validate_required([:order_number, :origin_gln, :destination_gln])
    |> validate_inclusion(:status, ~w(draft submitted approved rejected))
  end
end
