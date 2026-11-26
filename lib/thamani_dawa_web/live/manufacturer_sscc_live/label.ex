defmodule ThamaniDawaWeb.ManufacturerSsccLive.Label do
  @moduledoc """
  The one shipper label, shown as a modal over the shipper detail.
  Replaces the old Case label page and the Print SSCC labels dialog.
  """

  use ThamaniDawaWeb, :html

  attr :sscc, :map, required: true
  attr :product_name, :string, default: nil
  attr :batch_count, :integer, default: 1
  attr :on_cancel, JS, required: true

  def modal(assigns) do
    ~H"""
    <.td_modal
      id="shipper-label-modal"
      show
      width={480}
      title="Shipper label"
      subtitle={"SSCC #{@sscc.code} · #{@sscc.count_of_trade_items} units"}
      on_cancel={@on_cancel}
    >
      <:body>
        <div class="flex justify-center">
          <.sheet sscc={@sscc} product_name={@product_name} />
        </div>
      </:body>
      <:footer>
        <.td_button type="button" label="Cancel" phx-click={@on_cancel} />
        <.td_button
          id="print-manufacturer-label"
          type="button"
          variant="primary"
          glyph="printer"
          label="Print label"
          phx-hook="LabelPrint"
          data-print-target={"#sscc-label-content-#{@sscc.id}"}
          data-label-size="100mm auto"
        />
      </:footer>
    </.td_modal>
    """
  end

  attr :sscc, :map, required: true
  attr :product_name, :string, default: nil
  attr :id_prefix, :string, default: "sscc-label"

  def sheet(assigns) do
    ~H"""
    <div
      id={"#{@id_prefix}-content-#{@sscc.id}"}
      class="td-shipper-label mx-auto my-0 w-[400px] border-2 border-solid border-black bg-white p-0 font-sans text-black printable-sscc-label"
    >
      <div class="flex font-sans text-black">
        <div
          id={"#{@id_prefix}-from-#{@sscc.id}"}
          class="flex-1 border-r-2 border-r-black border-solid p-2"
        >
          <div class="mb-1 font-bold">From Address</div>
          <div class="whitespace-pre-line">{party_lines(@sscc, :from)}</div>
        </div>
        <div id={"#{@id_prefix}-to-#{@sscc.id}"} class="flex-1 p-2 text-black">
          <div><strong>To Address</strong></div>
          <div class="whitespace-pre-line">{party_lines(@sscc, :to)}</div>
        </div>
      </div>

      <div class="px-2.5 py-0">
        <div class="mb-3 flex items-start gap-x-3 border-t-2 border-t-black border-solid pt-[8px]">
          <div class="flex min-w-0 flex-1 flex-col">
            <span class="mb-0.5 text-[12px] text-black">SSCC</span>
            <span class="whitespace-nowrap text-[16px] font-bold tracking-tight text-black">{@sscc.code}</span>
          </div>
          <div class="grid min-w-0 flex-1 flex-col justify-end">
            <span class="mb-0.5 text-[12px] text-black">QUANTITY</span>
            <span id={"#{@id_prefix}-quantity-#{@sscc.id}"} class="text-[18px] font-bold text-black">{@sscc.count_of_trade_items}</span>
          </div>
        </div>

        <div class="mb-3 flex items-start gap-x-3">
          <div class="flex min-w-0 flex-1 flex-col">
            <span class="mb-0.5 text-[12px] text-black">CONTENT</span>
            <span class="text-[18px] font-bold text-black">{gtin14(@sscc)}</span>
          </div>
          <div class="grid min-w-0 flex-1 flex-col justify-end">
            <span class="mb-0.5 text-[12px] text-black">EXPIRY</span>
            <span class="text-[18px] font-bold text-black">{date_ai(@sscc.expiry_date)}</span>
          </div>
        </div>

        <div class="mb-3 flex items-start gap-x-3">
          <div class="flex min-w-0 flex-1 flex-col">
            <span class="mb-0.5 text-[12px] text-black">BATCH/LOT</span>
            <span class="break-all text-[18px] font-bold text-black">{@sscc.batch}</span>
          </div>
          <div class="grid min-w-0 flex-1 flex-col justify-end">
            <span class="mb-0.5 text-[12px] text-black">PROD DATE</span>
            <span class="text-[18px] font-bold text-black">{date_ai(@sscc.production_date)}</span>
          </div>
        </div>

        <div class="mb-3 flex items-start gap-x-3 border-b-2 border-b-black border-solid pb-[8px]">
          <div class="flex min-w-0 flex-1 flex-col">
            <span class="mb-0.5 text-[12px] text-black">MATERIAL DESCRIPTION</span>
            <span class="break-words text-[14px] font-bold text-black">{@product_name || "—"}</span>
          </div>
          <div class="grid min-w-0 flex-1 flex-col justify-end">
            <span class="mb-0.5 text-[12px] text-black">ORDER NUMBER</span>
            <span
              id={"#{@id_prefix}-order-number-#{@sscc.id}"}
              class="text-[18px] font-bold text-black"
            >{@sscc.order_number}</span>
          </div>
        </div>

        <div class="mt-[10px] flex items-start pb-[10px] pl-[35px]">
          <div class="mr-[15px] w-[110px]">
            <canvas
              id={"#{@id_prefix}-barcode-#{@sscc.id}"}
              phx-hook="DataMatrix"
              phx-update="ignore"
              data-barcode={barcode_payload(@sscc)}
              class="h-[120px] w-[120px]"
            ></canvas>
          </div>
          <div class="mt-[10px] flex-1 font-sans text-[12px] leading-[1.3] text-black">
            <div :for={{ai, value} <- ai_elements(@sscc)}>({ai}) {value}</div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp ai_elements(sscc) do
    [
      {"00", sscc.code},
      {"01", gtin14(sscc)},
      {"10", sscc.batch},
      {"17", date_ai(sscc.expiry_date)},
      {"11", date_ai(sscc.production_date)},
      {"37", sscc.count_of_trade_items && to_string(sscc.count_of_trade_items)}
    ]
    |> Enum.reject(fn {_ai, value} -> value in [nil, ""] end)
  end

  # gs1_admin feeds a raw, GS-delimited element string to a plain DataMatrix
  # encoder (no AI parsing). This mirrors that payload exactly, including the
  # leading and trailing group separators.
  def barcode_payload(sscc) do
    gs = <<29>>

    parts =
      [
        gs <> "00" <> to_string(sscc.code) <> gs,
        gtin14(sscc) && "01" <> gtin14(sscc),
        ai_part(gs, "10", sscc.batch),
        ai_part(gs, "17", date_ai(sscc.expiry_date)),
        ai_part(gs, "11", date_ai(sscc.production_date)),
        ai_part(gs, "37", sscc.count_of_trade_items)
      ]
      |> Enum.reject(&is_nil/1)

    Enum.join(parts) <> gs
  end

  defp ai_part(_gs, _ai, nil), do: nil
  defp ai_part(gs, ai, value), do: ai <> to_string(value) <> gs

  defp gtin14(sscc), do: sscc.gtin && String.pad_leading(sscc.gtin, 14, "0")

  defp date_ai(nil), do: nil
  defp date_ai(date), do: Calendar.strftime(date, "%y%m%d")

  defp party_lines(sscc, prefix) do
    [
      party(sscc, :"#{prefix}_company_name"),
      party(sscc, :"#{prefix}_address"),
      party(sscc, :"#{prefix}_gln") && "GLN #{party(sscc, :"#{prefix}_gln")}"
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
  end

  defp party(sscc, field) do
    (sscc.pallet && Map.get(sscc.pallet, field)) || Map.get(sscc, field)
  end
end
