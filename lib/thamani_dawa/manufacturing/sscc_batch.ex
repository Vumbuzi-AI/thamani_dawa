defmodule ThamaniDawa.Manufacturing.SsccBatch do
  use Ecto.Schema
  import Ecto.Changeset

  schema "manufacturer_sscc_batches" do
    belongs_to :shipper_sscc, ThamaniDawa.Manufacturing.ShipperSscc,
      foreign_key: :manufacturer_shipper_sscc_id

    belongs_to :batch, ThamaniDawa.Manufacturing.Batch, foreign_key: :manufacturer_batch_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(sscc_batch, attrs) do
    sscc_batch
    |> cast(attrs, [:manufacturer_shipper_sscc_id, :manufacturer_batch_id])
    |> validate_required([:manufacturer_shipper_sscc_id, :manufacturer_batch_id])
    |> unique_constraint([:manufacturer_shipper_sscc_id, :manufacturer_batch_id])
  end
end
