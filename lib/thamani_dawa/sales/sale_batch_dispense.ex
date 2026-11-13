defmodule ThamaniDawa.Sales.SaleBatchDispense do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sale_batch_dispenses" do
    field :quantity, :integer
    field :dispensed_at, :utc_datetime

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :sale_item, ThamaniDawa.Sales.SaleItem
    belongs_to :batch, ThamaniDawa.Batches.Batch
    belongs_to :dispensed_by, ThamaniDawa.Accounts.User, foreign_key: :dispensed_by_id

    timestamps(type: :utc_datetime)
  end

  def changeset(batch_dispense, attrs) do
    batch_dispense
    |> cast(attrs, [:sale_item_id, :batch_id, :quantity, :dispensed_by_id, :dispensed_at])
    |> validate_required([:sale_item_id, :batch_id, :quantity, :dispensed_at])
    |> validate_number(:quantity, greater_than: 0)
    |> foreign_key_constraint(:sale_item_id)
    |> foreign_key_constraint(:batch_id)
    |> foreign_key_constraint(:dispensed_by_id)
  end
end
