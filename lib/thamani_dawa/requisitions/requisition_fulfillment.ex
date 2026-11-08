defmodule ThamaniDawa.Requisitions.RequisitionFulfillment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "requisition_fulfillments" do
    field :dispatched_quantity, :integer
    field :received_quantity, :integer
    field :received_at, :utc_datetime

    belongs_to :requisition_line, ThamaniDawa.Requisitions.RequisitionLine
    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :source_batch, ThamaniDawa.Batches.Batch
    belongs_to :dispatched_batch, ThamaniDawa.Batches.Batch
    belongs_to :dispatched_by, ThamaniDawa.Accounts.User
    belongs_to :received_by, ThamaniDawa.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(fulfillment, attrs) do
    fulfillment
    |> cast(attrs, [
      :requisition_line_id,
      :organization_id,
      :source_batch_id,
      :dispatched_batch_id,
      :dispatched_quantity,
      :received_quantity,
      :dispatched_by_id,
      :received_by_id,
      :received_at
    ])
    |> validate_required([
      :requisition_line_id,
      :organization_id,
      :source_batch_id,
      :dispatched_batch_id,
      :dispatched_quantity
    ])
    |> validate_number(:dispatched_quantity, greater_than: 0)
    |> validate_number(:received_quantity, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:dispatched_batch_id)
    |> unique_constraint(:dispatched_batch_id)
  end
end
