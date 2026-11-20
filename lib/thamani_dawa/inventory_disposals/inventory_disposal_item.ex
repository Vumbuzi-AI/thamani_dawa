defmodule ThamaniDawa.InventoryDisposals.InventoryDisposalItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.InventoryDisposals.InventoryDisposal
  alias ThamaniDawa.Organizations.Organization

  schema "inventory_disposal_items" do
    field :available_quantity, :integer
    field :quantity, :integer
    field :notes, :string

    belongs_to :organization, Organization
    belongs_to :inventory_disposal, InventoryDisposal
    belongs_to :batch, Batch

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for adding a batch to a disposal, requesting `quantity` units be
  disposed. `quantity` must be positive and no more than `available_quantity`
  (the batch's `remaining_quantity` snapshotted at add-time) — partial
  disposal of a batch is allowed, but not disposing more than exists.
  """
  def create_changeset(item, attrs) do
    item
    |> cast(attrs, [
      :batch_id,
      :available_quantity,
      :quantity,
      :organization_id,
      :inventory_disposal_id,
      :notes
    ])
    |> validate_required([
      :batch_id,
      :available_quantity,
      :quantity,
      :organization_id,
      :inventory_disposal_id
    ])
    |> validate_number(:available_quantity, greater_than_or_equal_to: 0)
    |> validate_number(:quantity, greater_than: 0)
    |> validate_quantity_within_available()
    |> unique_constraint(:batch_id,
      name: :inventory_disposal_items_inventory_disposal_id_batch_id_index,
      message: "this batch is already included in this disposal"
    )
  end

  defp validate_quantity_within_available(%{valid?: false} = changeset), do: changeset

  defp validate_quantity_within_available(changeset) do
    quantity = get_field(changeset, :quantity)
    available = get_field(changeset, :available_quantity)

    if is_integer(quantity) and is_integer(available) and quantity > available do
      add_error(changeset, :quantity, "cannot exceed the available quantity")
    else
      changeset
    end
  end
end
