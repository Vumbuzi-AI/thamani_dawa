defmodule ThamaniDawa.Prescriptions.BatchDispense do
  use Ecto.Schema
  import Ecto.Changeset

  schema "prescription_batch_dispenses" do
    field :quantity, :integer
    field :dispensed_at, :utc_datetime

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :prescription_item, ThamaniDawa.Prescriptions.PrescriptionItem
    belongs_to :batch, ThamaniDawa.Batches.Batch
    belongs_to :dispensed_by, ThamaniDawa.Accounts.User, foreign_key: :dispensed_by_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(batch_dispense, attrs) do
    batch_dispense
    |> cast(attrs, [
      :organization_id,
      :prescription_item_id,
      :batch_id,
      :quantity,
      :dispensed_by_id,
      :dispensed_at
    ])
    |> validate_required([:organization_id, :prescription_item_id, :batch_id, :quantity])
    |> validate_number(:quantity, greater_than: 0)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:prescription_item_id)
    |> foreign_key_constraint(:batch_id)
    |> foreign_key_constraint(:dispensed_by_id)
  end
end
