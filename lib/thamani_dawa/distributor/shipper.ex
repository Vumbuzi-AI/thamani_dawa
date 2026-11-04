defmodule ThamaniDawa.Distributor.Shipper do
  @moduledoc """
  A logistics unit (case) inside a shipment. It receives exactly one SSCC
  when its shipment is approved. On approval its contents are snapshotted:
  a shipper holding a single GTIN/batch/dates combination records them; a
  mixed shipper records none.
  """

  use Ecto.Schema

  schema "distributor_shippers" do
    field :sequence, :integer
    field :name, :string
    field :sscc, :string
    field :gtin, :string
    field :batch, :string
    field :production_date, :date
    field :expiry_date, :date
    field :product_name, :string
    field :unit_count, :integer
    field :sscc_assigned_at, :utc_datetime

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :shipment, ThamaniDawa.Distributor.Shipment
    has_many :items, ThamaniDawa.Distributor.ShipmentItem, preload_order: [asc: :scanned_at]

    timestamps(type: :utc_datetime)
  end
end
