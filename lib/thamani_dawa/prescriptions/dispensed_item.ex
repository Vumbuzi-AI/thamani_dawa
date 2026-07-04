defmodule ThamaniDawa.Prescriptions.DispensedItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "dispensed_items" do
    field :organization_id, :id
    field :prescription_item_id, :id
    field :batch_id, :id
    field :quantity, :integer
    field :unit_price, :decimal
    field :pharmacist_id, :id
    field :is_verified, :boolean, default: false
    field :dispensed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(dispensed_item, attrs) do
    dispensed_item
    |> cast(attrs, [
      :prescription_item_id,
      :batch_id,
      :quantity,
      :unit_price,
      :pharmacist_id,
      :is_verified,
      :dispensed_at
    ])
    |> validate_required([:prescription_item_id, :batch_id, :quantity])
    |> validate_number(:quantity, greater_than: 0)
    |> foreign_key_constraint(:prescription_item_id)
    |> foreign_key_constraint(:batch_id)
    |> foreign_key_constraint(:pharmacist_id)
  end
end
