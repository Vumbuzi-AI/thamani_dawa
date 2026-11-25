defmodule ThamaniDawaWeb.ManufacturerSsccLive.Label do
  @moduledoc """
  The one shipper label: a 4 × 6 in GS1 logistics sheet with a Data Matrix.
  """

  use ThamaniDawaWeb, :html

  attr :sscc, :map, required: true
  attr :product_name, :string, default: nil
  attr :on_cancel, JS, required: true

  def modal(assigns) do
    ~H"""
    <.td_modal
      id="shipper-label-modal"
      show
      width={440}
      title="Shipper label"
      subtitle={"4 × 6 in · #{@sscc.count_of_trade_items} units"}
      on_cancel={@on_cancel}
    >
      <:body>
        <div class="td-shipper-stage">
          <.sheet sscc={@sscc} product_name={@product_name} />
        </div>
      </:body>
      <:footer>
        <.td_button type="button" label="Cancel" phx-click={@on_cancel} />
        <.td_button
          id="download-manufacturer-label-svg"
          type="button"
          glyph="download-simple"
          label="SVG"
          phx-hook="LabelSvgDownload"
          data-role="download-label-svg"
          data-sscc={@sscc.code}
          data-gs1-text={gs1_text(@sscc)}
          data-quantity={@sscc.count_of_trade_items}
          data-gtin={gtin14(@sscc.gtin)}
          data-batch={@sscc.batch}
          data-production={svg_date(@sscc.production_date)}
          data-expiry={svg_date(@sscc.expiry_date)}
          data-material-description={@product_name}
          data-order-number={@sscc.order_number}
          data-from-company={party(@sscc, :from_company_name)}
          data-from-address={party(@sscc, :from_address)}
          data-to-company={party(@sscc, :to_company_name)}
          data-to-address={party(@sscc, :to_address)}
        />
        <.td_button
          id="print-manufacturer-label"
          type="button"
          variant="primary"
          glyph="printer"
          label="Print label"
          phx-hook="LabelPrint"
          data-print-target={"#sscc-label-content-#{@sscc.id}"}
          data-label-size="4in 6in"
        />
      </:footer>
    </.td_modal>
    """
  end

  attr :sscc, :map, required: true
  attr :product_name, :string, default: nil
  attr :id, :string, default: nil
  attr :barcode_id, :string, default: nil
  attr :named, :boolean, default: true

  def sheet(assigns) do
    sscc = assigns.sscc

    assigns =
      assigns
      |> assign(:id, assigns.id || "sscc-label-content-#{sscc.id}")
      |> assign(:barcode_id, assigns.barcode_id || "sscc-barcode-#{sscc.id}")
      |> assign(:ais, ai_elements(sscc))

    ~H"""
    <div
      id={@id}
      class="td-shipper-label printable-sscc-label"
    >
      <div class="td-shipper-label-split">
        <div id={@named && "sscc-label-from"}>
          <span class="td-shipper-cap">From</span>
          <strong>{party(@sscc, :from_company_name) || "—"}</strong>
          <span :if={party(@sscc, :from_address)}>{party(@sscc, :from_address)}</span>
          <span :if={party(@sscc, :from_gln)} class="td-shipper-mono">GLN {party(@sscc, :from_gln)}</span>
        </div>
        <div id={@named && "sscc-label-to"}>
          <span class="td-shipper-cap">To</span>
          <strong>{party(@sscc, :to_company_name) || "—"}</strong>
          <span :if={party(@sscc, :to_address)}>{party(@sscc, :to_address)}</span>
          <span :if={party(@sscc, :to_gln)} class="td-shipper-mono">GLN {party(@sscc, :to_gln)}</span>
        </div>
      </div>

      <div class="td-shipper-label-sscc">
        <span class="td-shipper-cap">SSCC</span>
        <strong class="td-shipper-mono">{@sscc.code}</strong>
      </div>

      <div class="td-shipper-label-grid">
        <div>
          <span class="td-shipper-cap">Content</span>
          <strong class="td-shipper-mono">{gtin14(@sscc.gtin)}</strong>
          <span :if={@product_name}>{@product_name}</span>
        </div>
        <div id={@named && "sscc-label-quantity"}>
          <span class="td-shipper-cap">Count</span>
          <strong>{@sscc.count_of_trade_items} units</strong>
        </div>
        <div>
          <span class="td-shipper-cap">Batch</span>
          <strong class="td-shipper-mono">{@sscc.batch || "—"}</strong>
        </div>
        <div>
          <span class="td-shipper-cap">Expiry</span>
          <strong>{long_date(@sscc.expiry_date)}</strong>
        </div>
        <div id={@named && "sscc-label-order-number"}>
          <span class="td-shipper-cap">Order</span>
          <strong>{@sscc.order_number || "—"}</strong>
        </div>
        <div>
          <span class="td-shipper-cap">Prod date</span>
          <strong>{long_date(@sscc.production_date)}</strong>
        </div>
      </div>

      <div class="td-shipper-label-code">
        <canvas
          id={@barcode_id}
          phx-hook="DataMatrix"
          phx-update="ignore"
          data-gs1-text={gs1_text(@sscc)}
        >
        </canvas>
        <div class="td-shipper-hri">
          <span :for={{ai, value} <- @ais} class="td-shipper-mono">({ai}){value}</span>
        </div>
      </div>
    </div>
    """
  end

  defp ai_elements(sscc) do
    [
      {"00", sscc.code},
      {"02", gtin14(sscc.gtin)},
      {"10", sscc.batch},
      {"17", date_ai(sscc.expiry_date)},
      {"11", date_ai(sscc.production_date)},
      {"37", sscc.count_of_trade_items && to_string(sscc.count_of_trade_items)},
      {"400", sscc.order_number}
    ]
    |> Enum.reject(fn {_ai, value} -> value in [nil, ""] end)
  end

  def gs1_text(sscc), do: Enum.map_join(ai_elements(sscc), fn {ai, v} -> "(#{ai})#{v}" end)
  defp date_ai(nil), do: nil
  defp date_ai(date), do: Calendar.strftime(date, "%y%m%d")
  defp svg_date(nil), do: nil
  defp svg_date(date), do: Calendar.strftime(date, "%d %b %Y")
  defp long_date(nil), do: "—"
  defp long_date(date), do: ThamaniDawaWeb.TimeFormat.date(date)

  defp gtin14(nil), do: nil
  defp gtin14(gtin), do: String.pad_leading(gtin, 14, "0")

  defp party(sscc, field) do
    (sscc.pallet && Map.get(sscc.pallet, field)) || Map.get(sscc, field)
  end
end
