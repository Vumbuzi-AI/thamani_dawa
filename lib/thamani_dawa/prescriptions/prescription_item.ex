defmodule ThamaniDawa.Prescriptions.PrescriptionItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "prescription_items" do
    field :organization_id, :id
    field :prescription_id, :id
    field :product_id, :id
    field :quantity_prescribed, :integer
    field :dosage_instructions, :string
    field :frequency, :string
    field :duration_in_days, :integer
    field :route_of_administration, :string
    field :quantity_dispensed, :integer, default: 0
    field :is_verified, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(prescription_item, attrs) do
    prescription_item
    |> cast(attrs, [
      :organization_id,
      :product_id,
      :quantity_prescribed,
      :dosage_instructions,
      :frequency,
      :duration_in_days,
      :route_of_administration,
      :quantity_dispensed,
      :is_verified
    ])
    |> validate_required([:product_id, :quantity_prescribed])
    |> validate_number(:quantity_prescribed, greater_than: 0)
    |> validate_number(:quantity_dispensed, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:product_id)
    |> foreign_key_constraint(:prescription_id)
  end
end
