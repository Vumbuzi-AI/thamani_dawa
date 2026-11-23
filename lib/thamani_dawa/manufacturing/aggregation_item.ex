defmodule ThamaniDawa.Manufacturing.AggregationItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "manufacturer_aggregation_items" do
    field :raw_data_matrix, :string
    field :serial, :string
    field :gtin, :string
    field :validation_status, :string
    field :scanned_at, :utc_datetime

    belongs_to :aggregation, ThamaniDawa.Manufacturing.Aggregation,
      foreign_key: :manufacturer_aggregation_id

    belongs_to :organization, ThamaniDawa.Organizations.Organization

    belongs_to :serial_record, ThamaniDawa.Manufacturing.Serial,
      foreign_key: :manufacturer_serial_id

    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :manufacturer_aggregation_id,
      :organization_id,
      :manufacturer_serial_id,
      :raw_data_matrix,
      :serial,
      :gtin,
      :validation_status,
      :scanned_at
    ])
    |> validate_required([:serial, :validation_status])
    |> unique_constraint([:manufacturer_aggregation_id, :serial])
  end
end
