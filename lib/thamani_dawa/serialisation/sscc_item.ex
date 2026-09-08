defmodule ThamaniDawa.Serialisation.SsccItem do
  @moduledoc """
  What is inside one logistics unit. Several rows against the same SSCC means
  a mixed pallet — which is still exactly one billable serial (§2.4.4).
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "serial_sscc_items" do
    field :gtin, :string
    field :count, :integer, default: 0
    field :items, :integer, default: 0

    belongs_to :sscc, ThamaniDawa.Serialisation.Sscc

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:gtin, :count, :items, :sscc_id])
    |> validate_required([:gtin, :sscc_id])
    |> validate_number(:count, greater_than_or_equal_to: 0)
    |> validate_number(:items, greater_than_or_equal_to: 0)
    |> ThamaniDawa.Gtin.validate_gtin()
  end
end
