defmodule ThamaniDawa.StockTakes.StockTakeItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.StockTakes.StockTake

  schema "stock_take_items" do
    field :expected_quantity, :integer
    field :counted_quantity, :integer
    field :variance, :integer
    field :counted_at, :utc_datetime
    field :notes, :string

    belongs_to :organization, Organization
    belongs_to :stock_take, StockTake
    belongs_to :batch, Batch
    belongs_to :counted_by, User, foreign_key: :counted_by_id

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for adding a batch to a stock take session."
  def create_changeset(item, attrs) do
    item
    |> cast(attrs, [:batch_id, :expected_quantity, :organization_id, :stock_take_id])
    |> validate_required([:batch_id, :expected_quantity, :organization_id, :stock_take_id])
    |> validate_number(:expected_quantity, greater_than_or_equal_to: 0)
    |> unique_constraint(:batch_id,
      name: :stock_take_items_stock_take_id_batch_id_index,
      message: "this batch is already included in the stock take"
    )
  end

  @doc "Changeset for recording the physical count for an item."
  def count_changeset(item, attrs) do
    item
    |> cast(attrs, [:counted_quantity, :counted_by_id, :counted_at, :notes])
    |> validate_required([:counted_quantity, :counted_by_id, :counted_at])
    |> validate_number(:counted_quantity, greater_than_or_equal_to: 0)
    |> compute_variance()
  end

  defp compute_variance(%{valid?: false} = changeset), do: changeset

  defp compute_variance(changeset) do
    counted = get_field(changeset, :counted_quantity)
    expected = get_field(changeset, :expected_quantity)

    if is_integer(counted) and is_integer(expected) do
      put_change(changeset, :variance, counted - expected)
    else
      changeset
    end
  end
end
