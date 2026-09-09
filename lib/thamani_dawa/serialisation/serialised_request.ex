defmodule ThamaniDawa.Serialisation.SerialisedRequest do
  @moduledoc """
  The serialised Data Matrix generation form (ui.md §11), mapping to
  `POST /api/create_serialised_datamatrix` (serialisation.md §4.3).

  `shipper_count = trunc(trade_item_qty / shipper_qty)`, and GS1 authorizes
  `trade_item_qty + shipper_count` serials against the member's plan. That
  total is shown on the form so the member sees what the run will cost before
  submitting — it is **not** checked locally: GS1 remains the sole enforcer
  (§6).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @required ~w(gtin batch production_date expiry_date trade_item_qty shipper_qty)a
  @optional ~w(order_number customer_part_number material_description
               from_company_name from_address to_company_name to_address)a

  @primary_key false
  embedded_schema do
    field :gtin, :string
    field :batch, :string
    field :production_date, :date
    field :expiry_date, :date

    field :trade_item_qty, :integer
    field :shipper_qty, :integer

    field :order_number, :string
    field :customer_part_number, :string
    field :material_description, :string

    field :from_company_name, :string
    field :from_address, :string
    field :to_company_name, :string
    field :to_address, :string
  end

  @doc false
  def changeset(request, attrs) do
    request
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_number(:trade_item_qty, greater_than: 0)
    |> validate_number(:shipper_qty, greater_than: 0)
    |> ThamaniDawa.Gtin.validate_gtin()
    |> validate_shipper_fits()
    |> validate_expiry_after_production()
  end

  defp validate_shipper_fits(changeset) do
    trade = get_field(changeset, :trade_item_qty)
    shipper = get_field(changeset, :shipper_qty)

    if trade && shipper && shipper > trade do
      add_error(changeset, :shipper_qty, "cannot be more than the total number of trade items")
    else
      changeset
    end
  end

  defp validate_expiry_after_production(changeset) do
    production = get_field(changeset, :production_date)
    expiry = get_field(changeset, :expiry_date)

    if production && expiry && Date.compare(expiry, production) == :lt do
      add_error(changeset, :expiry_date, "must be on or after the production date")
    else
      changeset
    end
  end

  @doc "How many shippers a run of this shape produces (§4.3)."
  def shipper_count(%__MODULE__{trade_item_qty: trade, shipper_qty: shipper})
      when is_integer(trade) and is_integer(shipper) and shipper > 0,
      do: trunc(trade / shipper)

  def shipper_count(_request), do: 0

  @doc "The serials GS1 will authorize for this run: trade items plus shippers."
  def authorized_serials(%__MODULE__{trade_item_qty: trade} = request) when is_integer(trade),
    do: trade + shipper_count(request)

  def authorized_serials(_request), do: 0

  @doc """
  The `POST /api/create_serialised_datamatrix` body.

  `barcode` goes out as the 13 digits the platform demands, even though the
  canonical local form is GTIN-14 (§4.3).
  """
  def to_params(%__MODULE__{} = request) do
    with {:ok, gtin13} <- ThamaniDawa.Gtin.to_gtin13(request.gtin) do
      {:ok,
       %{
         barcode: gtin13,
         batch: request.batch,
         production: Date.to_iso8601(request.production_date),
         expiry: Date.to_iso8601(request.expiry_date),
         trade_item_qty: to_string(request.trade_item_qty),
         shipper_qty: to_string(request.shipper_qty),
         order_number: request.order_number,
         customer_part_number: request.customer_part_number
       }}
    end
  end

  @doc "The `serial_shipments` attributes recorded for a request."
  def to_shipment_attrs(%__MODULE__{} = request) do
    %{
      type: :serialised,
      batch: request.batch,
      production_date: request.production_date,
      expiry_date: request.expiry_date,
      order_number: request.order_number,
      customer_part_number: request.customer_part_number,
      material_description: request.material_description,
      from_address: request.from_address,
      to_address: request.to_address,
      from_company_name: request.from_company_name,
      to_company_name: request.to_company_name
    }
  end
end
