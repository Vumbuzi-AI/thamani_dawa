defmodule ThamaniDawa.Serialisation.ShipmentLine do
  @moduledoc """
  One GTIN on a shipment, with how many cases of it and how many items per
  case. A shipment with more than one line is a mixed pallet (§2.4.4).
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "serial_shipment_lines" do
    field :gtin, :string
    field :cases, :integer, default: 0
    field :items_per_case, :integer, default: 0

    belongs_to :shipment, ThamaniDawa.Serialisation.Shipment

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(line, attrs) do
    line
    |> cast(attrs, [:gtin, :cases, :items_per_case, :shipment_id])
    |> validate_required([:gtin])
    |> validate_number(:cases, greater_than_or_equal_to: 0)
    |> validate_number(:items_per_case, greater_than_or_equal_to: 0)
    |> ThamaniDawa.Gtin.validate_gtin()
  end
end
