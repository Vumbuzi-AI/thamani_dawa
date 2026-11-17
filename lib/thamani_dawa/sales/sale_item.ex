defmodule ThamaniDawa.Sales.SaleItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sale_items" do
    field :quantity, :integer
    field :unit_price, :decimal
    field :is_verified, :boolean, default: false

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :sale, ThamaniDawa.Sales.Sale
    belongs_to :product, ThamaniDawa.Products.Product

    has_many :batch_dispenses, ThamaniDawa.Sales.SaleBatchDispense

    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:sale_id, :product_id, :quantity, :unit_price, :is_verified])
    |> validate_required([:sale_id, :product_id, :quantity, :unit_price])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:unit_price, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:sale_id)
    |> foreign_key_constraint(:product_id)
  end
end
