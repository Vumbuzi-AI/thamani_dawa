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
      width={880}
      title="Shipper label"
      subtitle={"SSCC #{@sscc.code} · #{@sscc.count_of_trade_items} units"}
      on_cancel={@on_cancel}
    >
      <:body>
        <div class="td-pack">
          <.sheet sscc={@sscc} product_name={@product_name} />
          <div>
            <.td_select
              id="shipper-label-size"
              name="label_size"
              label="Label size"
              value="100x150"
              options={[{"100 × 150 mm (4 × 6 in)", "100x150"}]}
            />
            <.td_input id="shipper-label-copies" name="copies" label="Copies" type="number" value="1" />
            <div class="td-choice is-on">
              <strong>This shipper</strong>
              <span class="td-note font-mono">{@sscc.code}</span>
            </div>
            <div class="td-choice" id="shipper-label-all">
              <strong>All {@batch_count} shippers in {@sscc.batch}</strong>
              <span class="td-note">One label per shipper, in SSCC order. Printing the batch is next.</span>
            </div>
            <p class="td-note">
              Printed at full size. The label carries the SSCC as a GS1-128 barcode with From, To, content, batch and expiry.
            </p>
          </div>
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
          data-label-size="4in 6in"
        />
      </:footer>
    </.td_modal>
    """
  end

  attr :sscc, :map, required: true
  attr :product_name, :string, default: nil

  def sheet(assigns) do
    ~H"""
    <div
      id={"sscc-label-content-#{@sscc.id}"}
      class="td-label-sheet printable-sscc-label"
    >
      <div class="td-label-grid">
        <div id="sscc-label-from" class="td-label-cell">
          <div>From</div>
          <strong>{party(@sscc, :from_company_name)}</strong>
          <div>{party(@sscc, :from_address)}</div>
          <div :if={party(@sscc, :from_gln)}>GLN {party(@sscc, :from_gln)}</div>
        </div>
        <div id="sscc-label-to" class="td-label-cell">
          <div>To</div>
          <strong>{party(@sscc, :to_company_name)}</strong>
          <div>{party(@sscc, :to_address)}</div>
          <div :if={party(@sscc, :to_gln)}>GLN {party(@sscc, :to_gln)}</div>
        </div>
      </div>
      <div class="td-label-grid">
        <div class="td-label-cell">
          <div>Shipper SSCC</div>
          <strong class="font-mono">{@sscc.code}</strong>
        </div>
        <div id="sscc-label-order-number" class="td-label-cell">
          <div>Order</div>
          <strong>{@sscc.order_number || "—"}</strong>
        </div>
      </div>
      <div class="td-label-grid">
        <div class="td-label-cell">
          <div>Content GTIN</div>
          <strong class="font-mono">{@sscc.gtin && String.pad_leading(@sscc.gtin, 14, "0")}</strong>
          <div>{@product_name}</div>
        </div>
        <div id="sscc-label-quantity" class="td-label-cell">
          <div>Count</div>
          <strong>{@sscc.count_of_trade_items} units</strong>
        </div>
      </div>
      <div class="td-label-grid">
        <div class="td-label-cell">
          <div>Batch</div>
          <strong class="font-mono">{@sscc.batch}</strong>
        </div>
        <div class="td-label-cell">
          <div>Expiry</div>
          <strong>{long_date(@sscc.expiry_date)}</strong>
        </div>
      </div>
      <div class="td-label-cell">
        <canvas
          id={"sscc-barcode-#{@sscc.id}"}
          phx-hook="DataMatrix"
          phx-update="ignore"
          data-gs1-text={gs1_text(@sscc)}
          class="size-[120px]"
        ></canvas>
        <div :for={{ai, value} <- ai_elements(@sscc)} class="font-mono">({ai}){value}</div>
      </div>
    </div>
    """
  end

  defp ai_elements(sscc) do
    [
      {"00", sscc.code},
      {"02", sscc.gtin && String.pad_leading(sscc.gtin, 14, "0")},
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
  defp long_date(nil), do: "—"
  defp long_date(date), do: ThamaniDawaWeb.TimeFormat.date(date)

  defp party(sscc, field) do
    (sscc.pallet && Map.get(sscc.pallet, field)) || Map.get(sscc, field)
  end
end
