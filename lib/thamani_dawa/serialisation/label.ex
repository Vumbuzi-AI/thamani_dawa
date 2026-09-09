defmodule ThamaniDawa.Serialisation.Label do
  @moduledoc """
  The label artwork contract (ui.md §10).

  A label is built here — never in a template — so the Data Matrix payload and
  the human-readable application identifiers printed beside it come from one
  list and cannot drift apart. `gs1_text/1` is what the barcode renderer
  encodes; `ai_lines/1` is what a human reads. Both walk the same `elements`.

  Nothing in here mints an identifier: every SSCC and serial arrives already
  issued by GS1 (§2.4.1). Codes are carried as strings end to end so a leading
  zero survives.
  """

  alias ThamaniDawa.Serialisation.SerialisedCode
  alias ThamaniDawa.Serialisation.Shipment
  alias ThamaniDawa.Serialisation.Sscc

  @enforce_keys [:kind, :elements]
  defstruct [
    :kind,
    :elements,
    :sscc,
    :gtin,
    :quantity,
    :batch,
    :expiry,
    :production,
    :serial,
    :order_number,
    :customer_part_number,
    :material_description,
    :from_company_name,
    :from_address,
    :to_company_name,
    :to_address,
    :sequence
  ]

  @type kind :: :pallet | :shipper | :primary
  @type t :: %__MODULE__{kind: kind(), elements: [{String.t(), String.t()}]}

  @doc """
  Builds a pallet (or case) SSCC label from a persisted SSCC and its shipment.

  `opts` carries what the SSCC row itself cannot know: `:gtin` (which of a
  mixed pallet's GTINs this label is being viewed under), `:quantity`, and the
  `:sequence` tuple rendered as `PALLET 1/1`.
  """
  @spec pallet(Sscc.t(), Shipment.t(), keyword()) :: t()
  def pallet(%Sscc{} = sscc, %Shipment{} = shipment, opts \\ []) do
    gtin = Keyword.get(opts, :gtin) || primary_gtin(sscc)
    quantity = Keyword.get(opts, :quantity) || quantity_for(sscc, gtin)

    %__MODULE__{
      kind: :pallet,
      sscc: sscc.code,
      gtin: gtin,
      quantity: quantity,
      batch: shipment.batch,
      expiry: shipment.expiry_date,
      production: shipment.production_date,
      order_number: shipment.order_number,
      customer_part_number: shipment.customer_part_number,
      material_description: shipment.material_description,
      from_company_name: shipment.from_company_name,
      from_address: shipment.from_address,
      to_company_name: shipment.to_company_name,
      to_address: shipment.to_address,
      sequence: Keyword.get(opts, :sequence),
      elements:
        elements([
          {"00", sscc.code},
          {"01", gtin},
          {"10", shipment.batch},
          {"17", ai_date(shipment.expiry_date)},
          {"11", ai_date(shipment.production_date)},
          {"37", quantity && to_string(quantity)},
          {"241", shipment.customer_part_number},
          {"400", shipment.order_number}
        ])
    }
  end

  @doc """
  Builds a shipper (case) label: the pallet fields plus the shipper's own
  serial under AI `(21)`.
  """
  @spec shipper(Sscc.t(), Shipment.t(), keyword()) :: t()
  def shipper(%Sscc{} = sscc, %Shipment{} = shipment, opts \\ []) do
    gtin = Keyword.get(opts, :gtin) || primary_gtin(sscc)
    quantity = Keyword.get(opts, :quantity) || quantity_for(sscc, gtin)
    serial = Keyword.get(opts, :serial)

    %__MODULE__{
      kind: :shipper,
      sscc: sscc.code,
      gtin: gtin,
      quantity: quantity,
      batch: shipment.batch,
      expiry: shipment.expiry_date,
      production: shipment.production_date,
      serial: serial,
      order_number: shipment.order_number,
      customer_part_number: shipment.customer_part_number,
      material_description: shipment.material_description,
      from_company_name: shipment.from_company_name,
      from_address: shipment.from_address,
      to_company_name: shipment.to_company_name,
      to_address: shipment.to_address,
      elements:
        elements([
          {"00", sscc.code},
          {"01", gtin},
          {"10", shipment.batch},
          {"17", ai_date(shipment.expiry_date)},
          {"11", ai_date(shipment.production_date)},
          {"37", quantity && to_string(quantity)},
          {"21", serial}
        ])
    }
  end

  @doc "Builds a primary (trade item) serial card."
  @spec primary(SerialisedCode.t(), Shipment.t()) :: t()
  def primary(%SerialisedCode{} = code, %Shipment{} = shipment) do
    %__MODULE__{
      kind: :primary,
      gtin: code.gtin,
      batch: shipment.batch,
      expiry: shipment.expiry_date,
      production: shipment.production_date,
      serial: code.serial,
      elements:
        elements([
          {"01", code.gtin},
          {"10", shipment.batch},
          {"17", ai_date(shipment.expiry_date)},
          {"11", ai_date(shipment.production_date)},
          {"21", code.serial}
        ])
    }
  end

  @doc """
  The GS1 element string the Data Matrix encodes, in the bracketed form
  `bwip-js`'s `gs1datamatrix` encoder parses: `(01)0616...(10)B12`.
  """
  @spec gs1_text(t()) :: String.t()
  def gs1_text(%__MODULE__{elements: elements}) do
    Enum.map_join(elements, "", fn {ai, value} -> "(#{ai})#{value}" end)
  end

  @doc "The human-readable AI lines printed beside the symbol, one per element."
  @spec ai_lines(t()) :: [String.t()]
  def ai_lines(%__MODULE__{elements: elements}) do
    Enum.map(elements, fn {ai, value} -> "(#{ai}) #{value}" end)
  end

  @doc """
  A date in the `YYMMDD` form GS1 AIs `(11)` and `(17)` use. `nil` in, `nil`
  out — an absent date must drop its element rather than print zeroes.
  """
  @spec ai_date(Date.t() | nil) :: String.t() | nil
  def ai_date(nil), do: nil
  def ai_date(%Date{} = date), do: Calendar.strftime(date, "%y%m%d")

  @doc """
  A filename stem for a downloaded label, e.g.
  `pallet-06164005056791-HC-2608-A-161640050000010001`.

  Every part is slugified so a batch with a slash cannot escape the filename.
  """
  @spec filename(t()) :: String.t()
  def filename(%__MODULE__{} = label) do
    [to_string(label.kind), label.gtin, label.batch, label.serial || label.sscc]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map_join("-", &slug/1)
  end

  defp slug(value) do
    value
    |> to_string()
    |> String.replace(~r/[^A-Za-z0-9]+/, "-")
    |> String.trim("-")
  end

  # An AI with no value is dropped, not printed empty: a Data Matrix carrying
  # "(400)" with nothing after it does not decode.
  defp elements(pairs) do
    Enum.reject(pairs, fn {_ai, value} -> value in [nil, ""] end)
  end

  defp primary_gtin(%Sscc{items: [%{gtin: gtin} | _rest]}), do: gtin
  defp primary_gtin(_sscc), do: nil

  defp quantity_for(%Sscc{items: items}, gtin) when is_list(items) do
    Enum.find_value(items, fn item -> if item.gtin == gtin, do: item.count end)
  end

  defp quantity_for(_sscc, _gtin), do: nil
end
