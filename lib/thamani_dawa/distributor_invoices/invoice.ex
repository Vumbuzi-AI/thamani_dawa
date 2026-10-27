defmodule ThamaniDawa.DistributorInvoices.Invoice do
  use Ecto.Schema
  import Ecto.Changeset

  schema "distributor_invoices" do
    field :number, :integer
    field :issued_at, :utc_datetime
    field :subtotal, :integer
    field :total, :integer

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :order, ThamaniDawa.DistributorOrders.Order
    belongs_to :shipment, ThamaniDawa.DistributorShipments.Shipment
    belongs_to :customer, ThamaniDawa.DistributorCustomers.Customer
    has_many :lines, ThamaniDawa.DistributorInvoices.InvoiceLine
    has_many :payments, ThamaniDawa.DistributorInvoices.Payment

    timestamps(type: :utc_datetime)
  end

  def changeset(invoice, attrs) do
    invoice
    |> cast(attrs, [:number, :issued_at, :subtotal, :total, :order_id, :shipment_id, :customer_id])
    |> validate_required([
      :number,
      :issued_at,
      :subtotal,
      :total,
      :order_id,
      :shipment_id,
      :customer_id
    ])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:order_id)
    |> foreign_key_constraint(:shipment_id)
    |> foreign_key_constraint(:customer_id)
    |> unique_constraint(:order_id)
    |> unique_constraint(:shipment_id)
    |> unique_constraint(:number, name: :distributor_invoices_organization_id_number_index)
  end
end
