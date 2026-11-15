defmodule ThamaniDawa.Distributor.ShipmentLineItem do
  @moduledoc """
  An intended product + quantity on a draft shipment — what "Generate pick
  list" allocates specific batches against. Distinct from `ShipmentItem`,
  which represents an already-scanned physical unit.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "distributor_shipment_line_items" do
    field :quantity, :integer

    belongs_to :shipment, ThamaniDawa.Distributor.Shipment
    belongs_to :product, ThamaniDawa.Products.Product

    timestamps(type: :utc_datetime)
  end

  def changeset(line_item, attrs) do
    line_item
    |> cast(attrs, [:product_id, :quantity])
    |> validate_required([:product_id, :quantity])
    |> validate_number(:quantity, greater_than: 0)
    |> foreign_key_constraint(:product_id)
    |> foreign_key_constraint(:shipment_id)
  end
end
