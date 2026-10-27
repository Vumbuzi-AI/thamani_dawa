defmodule ThamaniDawa.DistributorShipments.Shipment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "distributor_shipments" do
    field :destination, :string
    field :status, :string
    field :dispatched_at, :utc_datetime

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :customer, ThamaniDawa.DistributorCustomers.Customer
    belongs_to :warehouse, ThamaniDawa.Sites.Site
    belongs_to :order, ThamaniDawa.DistributorOrders.Order
    has_many :lines, ThamaniDawa.DistributorShipments.ShipmentLine
    has_many :cartons, ThamaniDawa.DistributorShipments.Carton

    timestamps(type: :utc_datetime)
  end

  def changeset(shipment, attrs) do
    shipment
    |> cast(attrs, [:order_id, :customer_id, :warehouse_id, :destination, :status, :dispatched_at])
    |> validate_required([:customer_id, :warehouse_id, :destination, :status])
    |> foreign_key_constraint(:customer_id)
    |> foreign_key_constraint(:warehouse_id)
    |> foreign_key_constraint(:order_id)
  end
end
