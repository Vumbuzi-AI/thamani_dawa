defmodule ThamaniDawa.StockTakes.StockTakeEntry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "stock_take_entries" do
    field :expected_quantity, :integer
    field :counted_quantity, :integer
    field :variance, :integer
    field :has_been_applied, :boolean, default: false
    field :notes, :string
    field :counted_at, :utc_datetime

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :stock_take, ThamaniDawa.StockTakes.StockTake
    belongs_to :batch, ThamaniDawa.Batches.Batch
    belongs_to :counted_by, ThamaniDawa.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating an entry when a stock take starts — one per batch at the site."
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:stock_take_id, :batch_id, :expected_quantity])
    |> validate_required([:stock_take_id, :batch_id, :expected_quantity])
    |> foreign_key_constraint(:stock_take_id)
    |> foreign_key_constraint(:batch_id)
    |> unique_constraint([:stock_take_id, :batch_id])
  end

  @doc """
  Changeset for recording a counted quantity against an existing entry. Only
  `:counted_quantity`/`:notes` are cast from caller attrs — `counted_by_id`/`counted_at` are
  system-controlled and must be `put_change/3`'d by the caller before `finish_count_changeset/1`
  validates them.
  """
  def count_changeset(entry, attrs) do
    entry
    |> cast(attrs, [:counted_quantity, :notes])
    |> validate_required([:counted_quantity])
    |> validate_number(:counted_quantity, greater_than_or_equal_to: 0)
    |> put_variance()
  end

  @doc "Validates counted_by_id/counted_at once the caller has put_change/3'd them."
  def finish_count_changeset(changeset) do
    changeset
    |> validate_required([:counted_by_id, :counted_at])
    |> foreign_key_constraint(:counted_by_id)
  end

  @doc "Marks an entry as applied to its batch's remaining_quantity during finalization."
  def apply_changeset(entry) do
    change(entry, has_been_applied: true)
  end

  defp put_variance(changeset) do
    counted = get_field(changeset, :counted_quantity)
    expected = get_field(changeset, :expected_quantity)

    if counted != nil and expected != nil do
      put_change(changeset, :variance, counted - expected)
    else
      changeset
    end
  end
end
