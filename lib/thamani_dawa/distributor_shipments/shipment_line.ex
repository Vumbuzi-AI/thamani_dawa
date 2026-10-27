defmodule ThamaniDawa.DistributorShipments.ShipmentLine do
  use Ecto.Schema
  import Ecto.Changeset

  schema "distributor_shipment_lines" do
    field :quantity, :integer
    field :unit_price, :integer

    belongs_to :shipment, ThamaniDawa.DistributorShipments.Shipment
    belongs_to :product, ThamaniDawa.Products.Product
    belongs_to :batch, ThamaniDawa.Batches.Batch
    belongs_to :carton, ThamaniDawa.DistributorShipments.Carton

    timestamps(type: :utc_datetime)
  end

  def changeset(line, attrs) do
    line
    |> cast(attrs, [:shipment_id, :product_id, :batch_id, :carton_id, :quantity, :unit_price])
    |> validate_required([:shipment_id, :product_id, :batch_id, :quantity, :unit_price])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:unit_price, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:shipment_id)
    |> foreign_key_constraint(:product_id)
    |> foreign_key_constraint(:batch_id)
  end
end
