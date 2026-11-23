defmodule ThamaniDawa.Manufacturing.ShipmentItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "manufacturer_shipment_items" do
    belongs_to :shipment, ThamaniDawa.Manufacturing.Shipment,
      foreign_key: :manufacturer_shipment_id

    belongs_to :shipper_sscc, ThamaniDawa.Manufacturing.ShipperSscc,
      foreign_key: :manufacturer_shipper_sscc_id

    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:manufacturer_shipment_id, :manufacturer_shipper_sscc_id])
    |> validate_required([:manufacturer_shipment_id, :manufacturer_shipper_sscc_id])
    |> unique_constraint(:manufacturer_shipper_sscc_id)
  end
end
