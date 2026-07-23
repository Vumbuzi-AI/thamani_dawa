defmodule ThamaniDawa.LabOrders.LabConsumableUsage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "lab_consumable_usage" do
    field :quantity, :integer
    field :purpose, :string
    field :used_at, :utc_datetime

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :lab_order, ThamaniDawa.LabOrders.LabOrder
    belongs_to :batch, ThamaniDawa.Batches.Batch
    belongs_to :used_by, ThamaniDawa.Accounts.User, foreign_key: :used_by_id

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
