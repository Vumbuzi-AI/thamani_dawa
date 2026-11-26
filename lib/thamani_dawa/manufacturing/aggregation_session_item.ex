defmodule ThamaniDawa.Manufacturing.AggregationSessionItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "manufacturer_aggregation_session_items" do
    field :raw_identifier, :string
    field :captured_at, :utc_datetime

    belongs_to :session, ThamaniDawa.Manufacturing.AggregationSession,
      foreign_key: :manufacturer_aggregation_session_id

    belongs_to :serial, ThamaniDawa.Manufacturing.Serial, foreign_key: :manufacturer_serial_id

    belongs_to :shipper_sscc, ThamaniDawa.Manufacturing.ShipperSscc,
      foreign_key: :manufacturer_shipper_sscc_id

    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :manufacturer_aggregation_session_id,
      :manufacturer_serial_id,
      :manufacturer_shipper_sscc_id,
      :raw_identifier,
      :captured_at
    ])
    |> validate_required([:manufacturer_aggregation_session_id, :raw_identifier, :captured_at])
    |> validate_parent()
    |> unique_constraint(:manufacturer_serial_id,
      name: :manufacturer_aggregation_session_items_serial_once_per_session
    )
    |> unique_constraint(:manufacturer_shipper_sscc_id,
      name: :manufacturer_aggregation_session_items_shipper_once_per_session
    )
  end

  defp validate_parent(changeset) do
    serial = get_field(changeset, :manufacturer_serial_id)
    shipper = get_field(changeset, :manufacturer_shipper_sscc_id)

    if is_nil(serial) == is_nil(shipper),
      do: add_error(changeset, :base, "must reference exactly one captured identifier"),
      else: changeset
  end
end
