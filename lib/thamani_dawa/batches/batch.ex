defmodule ThamaniDawa.Batches.Batch do
  use Ecto.Schema
  import Ecto.Changeset

  schema "batches" do
    field :organization_id, :id
    field :product_id, :id
    field :site_id, :id
    field :gtin, :string
    field :batch_no, :string
    field :serial, :string
    field :manufacture_date, :date
    field :expiry_date, :date
    field :quantity, :integer
    field :remaining_quantity, :integer
    field :cost_per_unit, :decimal
    field :supplier_id, :id
    field :received_by_id, :id
    field :received_at, :utc_datetime
    field :approver_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for dispatching a batch to a site. Approval fields are not set
  here — they are stamped later via `receive_changeset/2` when staff confirm
  physical receipt.
  """
  def changeset(batch, attrs) do
    batch
    |> cast(attrs, [
      :product_id,
      :site_id,
      :gtin,
      :batch_no,
      :serial,
      :manufacture_date,
      :expiry_date,
      :quantity,
      :remaining_quantity,
      :cost_per_unit,
      :supplier_id
    ])
    |> validate_required([
      :product_id,
      :site_id,
      :gtin,
      :batch_no,
      :expiry_date,
      :quantity
    ])
    |> ThamaniDawa.Gtin.validate_gtin()
    |> validate_expiry_date()
    |> validate_number(:quantity, greater_than_or_equal_to: 0)
    |> validate_number(:remaining_quantity, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:product_id)
    |> foreign_key_constraint(:site_id)
    |> foreign_key_constraint(:supplier_id)
  end

  defp validate_expiry_date(changeset) do
    validate_change(changeset, :expiry_date, fn :expiry_date, date ->
      if Date.compare(date, Date.utc_today()) == :gt do
        []
      else
        [expiry_date: "must be in the future"]
      end
    end)
  end

  @doc """
  Changeset for confirming receipt of a dispatched batch. Casting `:quantity`
  is optional — pass it when the amount actually received differs from what
  was dispatched, which also resets `remaining_quantity` to match (a pending
  batch can't yet have anything dispensed from it).
  """
  def receive_changeset(batch, attrs) do
    batch
    |> cast(attrs, [:received_by_id, :received_at, :approver_id, :quantity])
    |> validate_required([:received_by_id, :received_at, :approver_id])
    |> validate_number(:quantity, greater_than_or_equal_to: 0)
    |> put_remaining_quantity_from_received_quantity()
    |> foreign_key_constraint(:received_by_id)
    |> foreign_key_constraint(:approver_id)
  end

  defp put_remaining_quantity_from_received_quantity(changeset) do
    case get_change(changeset, :quantity) do
      nil -> changeset
      quantity -> put_change(changeset, :remaining_quantity, quantity)
    end
  end
end
