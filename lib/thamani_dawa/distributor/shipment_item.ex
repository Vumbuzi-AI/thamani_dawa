defmodule ThamaniDawa.Distributor.ShipmentItem do
  @moduledoc """
  One scanned primary unit, packed into a shipper.

  `validation_status` compares the scan to the organization's received
  batches:

    * `"ok"` — a received batch carries this GTIN + serial with matching
      batch number and dates
    * `"unknown_serial"` — no received batch carries this GTIN + serial
    * `"data_mismatch"` — the serial is known, but its batch number or dates
      differ from the received record

  `product_source` records where product details came from: `"previous_scan"`,
  `"catalogue"`, `"verified_by_gs1"`, or `"unverified"` (the GS1 registry was
  unreachable, so the scan was recorded without product detail).
  """

  use Ecto.Schema

  @validation_statuses ~w(ok unknown_serial data_mismatch)

  schema "distributor_shipment_items" do
    field :raw_data_matrix, :string
    field :gtin, :string
    field :batch, :string
    field :serial, :string
    field :production_date, :date
    field :expiry_date, :date
    field :product_name, :string
    field :product_source, :string
    field :validation_status, :string
    field :scanned_at, :utc_datetime

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :shipment, ThamaniDawa.Distributor.Shipment
    belongs_to :shipper, ThamaniDawa.Distributor.Shipper
    belongs_to :product, ThamaniDawa.Products.Product
    belongs_to :batch_record, ThamaniDawa.Batches.Batch, foreign_key: :batch_id

    belongs_to :scanned_by, ThamaniDawa.Distributor.MobileUser,
      foreign_key: :scanned_by_mobile_user_id

    timestamps(type: :utc_datetime)
  end

  def validation_statuses, do: @validation_statuses
end
