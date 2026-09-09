defmodule ThamaniDawa.Serialisation.SsccRequest do
  @moduledoc """
  The SSCC generation form (ui.md §11): what the member fills in before a
  single `POST /api/create_sscc` (serialisation.md §4.1).

  An embedded schema rather than a `Shipment` changeset, because the form
  carries a field that is a call parameter and not a shipment column —
  `count_of_trade_items` — and because nothing may be written to
  `serial_shipments` until the member submits.

  One call mints **one** SSCC (serialisation.md §8.4 is still outstanding), so
  the form has no pallet count: a multi-pallet consignment is several runs
  until GS1 accepts a quantity parameter.

  Everything GS1 marks required is required here too, so an obviously
  incomplete form is caught before it costs a round trip. Anything GS1 alone
  can judge (prefix, entitlement, allowance) is left to GS1 (§6).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @required ~w(gtin batch production_date expiry_date count_of_trade_items
               material_description order_number from_address to_address)a
  @optional ~w(customer_part_number from_company_name to_company_name facility_gln)a

  @primary_key false
  embedded_schema do
    field :gtin, :string
    field :batch, :string
    field :production_date, :date
    field :expiry_date, :date

    field :count_of_trade_items, :integer

    field :material_description, :string
    field :order_number, :string
    field :customer_part_number, :string

    field :facility_gln, :string
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
    |> validate_number(:count_of_trade_items, greater_than: 0)
    |> ThamaniDawa.Gtin.validate_gtin()
    |> validate_expiry_after_production()
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

  @doc "The `POST /api/create_sscc` body for a validated request (§4.1)."
  def to_params(%__MODULE__{} = request) do
    %{
      batch_info: [
        %{
          gtin: request.gtin,
          batch: request.batch,
          production_date: Date.to_iso8601(request.production_date),
          expiry_date: Date.to_iso8601(request.expiry_date)
        }
      ],
      address: %{from_address: request.from_address, to_address: request.to_address},
      count_of_trade_items: request.count_of_trade_items,
      material_description: request.material_description,
      order_number: request.order_number,
      customer_part_number: request.customer_part_number,
      facility_gln: request.facility_gln
    }
  end

  @doc "The `serial_shipments` attributes recorded for a request."
  def to_shipment_attrs(%__MODULE__{} = request) do
    %{
      type: :sscc,
      batch: request.batch,
      production_date: request.production_date,
      expiry_date: request.expiry_date,
      order_number: request.order_number,
      customer_part_number: request.customer_part_number,
      material_description: request.material_description,
      from_gln_id: request.facility_gln,
      from_address: request.from_address,
      to_address: request.to_address,
      from_company_name: request.from_company_name,
      to_company_name: request.to_company_name
    }
  end
end
