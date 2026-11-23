defmodule ThamaniDawa.Manufacturing.Serial do
  use Ecto.Schema
  import Ecto.Changeset

  schema "manufacturer_serials" do
    field :serial, :string

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :product, ThamaniDawa.Manufacturing.Product, foreign_key: :manufacturer_product_id
    belongs_to :batch, ThamaniDawa.Manufacturing.Batch, foreign_key: :manufacturer_batch_id

    belongs_to :shipper_sscc, ThamaniDawa.Manufacturing.ShipperSscc,
      foreign_key: :manufacturer_shipper_sscc_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(serial, attrs) do
    serial
    |> cast(attrs, [:serial, :manufacturer_shipper_sscc_id])
    |> update_change(:serial, fn
      value when is_binary(value) -> String.trim(value)
      value -> value
    end)
    |> validate_required([:serial])
    |> unique_constraint([:manufacturer_product_id, :serial])
  end
end
