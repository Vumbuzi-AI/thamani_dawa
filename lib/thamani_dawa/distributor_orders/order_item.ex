defmodule ThamaniDawa.DistributorOrders.OrderItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "distributor_order_items" do
    field :quantity, :integer
    field :quantity_allocated, :integer, default: 0
    field :allocation_processed, :boolean, default: false
    field :unit_price, :integer

    belongs_to :order, ThamaniDawa.DistributorOrders.Order
    belongs_to :product, ThamaniDawa.Products.Product

    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :product_id,
      :quantity,
      :quantity_allocated,
      :allocation_processed,
      :unit_price
    ])
    |> validate_required([:product_id, :quantity, :unit_price])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:quantity_allocated, greater_than_or_equal_to: 0)
    |> validate_number(:unit_price, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:product_id)
  end
end
