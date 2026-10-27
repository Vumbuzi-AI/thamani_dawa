defmodule ThamaniDawa.DistributorInvoices.InvoiceLine do
  use Ecto.Schema
  import Ecto.Changeset

  schema "distributor_invoice_lines" do
    field :quantity, :integer
    field :unit_price, :integer
    field :line_total, :integer

    belongs_to :invoice, ThamaniDawa.DistributorInvoices.Invoice
    belongs_to :product, ThamaniDawa.Products.Product

    timestamps(type: :utc_datetime)
  end

  def changeset(line, attrs) do
    line
    |> cast(attrs, [:invoice_id, :product_id, :quantity, :unit_price, :line_total])
    |> validate_required([:invoice_id, :product_id, :quantity, :unit_price, :line_total])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:unit_price, greater_than_or_equal_to: 0)
    |> validate_number(:line_total, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:invoice_id)
    |> foreign_key_constraint(:product_id)
  end
end
