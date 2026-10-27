defmodule ThamaniDawa.DistributorOrders.Order do
  use Ecto.Schema
  import Ecto.Changeset

  schema "distributor_orders" do
    field :status, Ecto.Enum,
      values: [:pending, :allocated, :dispatched, :cancelled],
      default: :pending

    field :ordered_at, :utc_datetime
    field :delivery_address, :string

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :customer, ThamaniDawa.DistributorCustomers.Customer
    has_many :items, ThamaniDawa.DistributorOrders.OrderItem, on_replace: :delete
    has_one :shipment, ThamaniDawa.DistributorShipments.Shipment, foreign_key: :order_id
    has_one :invoice, ThamaniDawa.DistributorInvoices.Invoice, foreign_key: :order_id

    timestamps(type: :utc_datetime)
  end

  def changeset(order, attrs) do
    order
    |> cast(attrs, [:customer_id, :status, :ordered_at, :delivery_address])
    |> validate_required([:customer_id, :status, :ordered_at])
    |> cast_assoc(:items, with: &ThamaniDawa.DistributorOrders.OrderItem.changeset/2)
    |> foreign_key_constraint(:customer_id)
  end
end
