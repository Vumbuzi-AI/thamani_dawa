defmodule ThamaniDawa.CustomerReturns.CustomerReturnItem do
  @moduledoc """
  A line of a customer return: a quantity of a product coming back from
  the customer, with the lot details (`batch_no`/`expiry_date`) captured
  off the physical returned goods. `condition` is the inspector's call on
  what to do with it, assigned during inspection; `batch_id` is nil until
  completion, when it's set to the new destination `Batch` created for
  this line.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @conditions [:sellable, :damaged, :quarantine]

  schema "customer_return_items" do
    field :quantity, :integer
    field :batch_no, :string
    field :expiry_date, :date
    field :serial, :string
    field :matched, :boolean, default: false
    field :condition, Ecto.Enum, values: @conditions

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :customer_return, ThamaniDawa.CustomerReturns.CustomerReturn
    belongs_to :product, ThamaniDawa.Products.Product
    belongs_to :batch, ThamaniDawa.Batches.Batch
    belongs_to :shipment_item, ThamaniDawa.Distributor.ShipmentItem

    timestamps(type: :utc_datetime)
  end

  def conditions, do: @conditions

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :quantity,
      :batch_no,
      :expiry_date,
      :serial,
      :matched,
      :organization_id,
      :customer_return_id,
      :product_id,
      :shipment_item_id
    ])
    |> validate_required(
      [:quantity, :batch_no, :expiry_date, :organization_id, :customer_return_id, :product_id],
      message: "can't be blank"
    )
    |> validate_number(:quantity, greater_than: 0)
    |> foreign_key_constraint(:customer_return_id)
    |> foreign_key_constraint(:product_id)
    |> foreign_key_constraint(:shipment_item_id)
    |> unique_constraint(:shipment_item_id,
      name: :customer_return_items_shipment_item_id_index,
      message: "is already on a return"
    )
  end

  @doc "Changeset applied by the inspector to assign this item's condition."
  def condition_changeset(item, attrs) do
    item
    |> cast(attrs, [:condition])
    |> validate_required([:condition], message: "can't be blank")
  end

  @doc "Changeset applied when completion assigns the new destination batch."
  def assign_batch_changeset(item, batch_id) do
    change(item, batch_id: batch_id)
  end
end
