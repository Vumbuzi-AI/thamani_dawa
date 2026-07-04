defmodule ThamaniDawa.LabOrders.LabConsumableUsage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "lab_consumable_usage" do
    field :organization_id, :id
    field :lab_order_id, :id
    field :batch_id, :id
    field :quantity, :integer
    field :used_by_id, :id
    field :purpose, :string
    field :used_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(lab_consumable_usage, attrs) do
    lab_consumable_usage
    |> cast(attrs, [:lab_order_id, :batch_id, :quantity, :used_by_id, :purpose, :used_at])
    |> validate_required([:batch_id, :quantity])
    |> validate_number(:quantity, greater_than: 0)
    |> foreign_key_constraint(:lab_order_id)
    |> foreign_key_constraint(:batch_id)
    |> foreign_key_constraint(:used_by_id)
  end
end
