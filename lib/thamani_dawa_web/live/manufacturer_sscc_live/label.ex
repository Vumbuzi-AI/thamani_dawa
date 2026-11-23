defmodule ThamaniDawaWeb.ManufacturerSsccLive.Label do
  @moduledoc """
  A printable GS1-128/DataMatrix label for a manufacturer shipper (or
  pallet) SSCC — browser-print and SVG-download, same pattern as
  `DistributorShipmentLive.Show`'s case labels; no server-side PDF stack.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    sscc =
      organization_id
      |> Manufacturing.get_sscc_group!(id)
      |> then(&Manufacturing.ensure_shipper_parties(organization_id, &1))

    {:ok,
     socket
     |> assign(:page_title, "SSCC label")
     |> assign(:sscc, sscc)}
  end

  # Same element strings as the gs1_admin pallet label:
  # (00) SSCC (02) content GTIN-14 — GS1 forbids (01) alongside (37), so
  # a logistic unit names its contents with (02) (10) batch (17) expiry (11) production
  # (37) quantity (400) order number — blanks are left out.
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

  defp gs1_text(sscc), do: Enum.map_join(ai_elements(sscc), fn {ai, v} -> "(#{ai})#{v}" end)

  defp date_ai(nil), do: nil
  defp date_ai(date), do: Calendar.strftime(date, "%y%m%d")

  defp long_date(nil), do: "—"
  defp long_date(date), do: Calendar.strftime(date, "%d %b %Y")

  defp party(sscc, field) do
    (sscc.pallet && Map.get(sscc.pallet, field)) || Map.get(sscc, field)
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :align, :string, default: "left"
  attr :id, :string, default: nil

  defp label_field(assigns) do
    ~H"""
    <div id={@id} class={["flex flex-1 flex-col", @align == "right" && "items-end text-right"]}>
      <span class="mb-0.5 text-[12px]">{@label}</span>
      <span class="text-[18px] font-bold leading-tight">{@value || "—"}</span>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/products"}
      crumb="Products"
    >
      <.td_page_header title="Case label" subtitle={@sscc.code} />

      <div
        id={"sscc-label-content-#{@sscc.id}"}
        class="printable-sscc-label mt-6 w-[400px] max-w-full border-2 border-black bg-white text-black"
        style="font-family: Arial, Helvetica, sans-serif"
      >
        <div class="flex">
          <div id="sscc-label-from" class="flex-1 border-r-2 border-black p-2">
            <div class="mb-1 font-bold">From Address</div>
            <div class="text-[13px] font-semibold">{party(@sscc, :from_company_name)}</div>
            <div class="whitespace-pre-line text-[13px]">{party(@sscc, :from_address)}</div>
            <div :if={party(@sscc, :from_gln)} class="text-[12px]">
              GLN {party(@sscc, :from_gln)}
            </div>
          </div>
          <div id="sscc-label-to" class="flex-1 p-2">
            <div class="mb-1 font-bold">To Address</div>
            <div class="text-[13px] font-semibold">{party(@sscc, :to_company_name)}</div>
            <div class="whitespace-pre-line text-[13px]">{party(@sscc, :to_address)}</div>
            <div :if={party(@sscc, :to_gln)} class="text-[12px]">GLN {party(@sscc, :to_gln)}</div>
          </div>
        </div>

        <div class="px-2.5">
          <div class="mb-3 flex items-start border-t-2 border-black pt-2">
            <div class="flex flex-1 flex-col">
              <span class="mb-0.5 text-[12px]">SSCC</span>
              <span class="whitespace-nowrap text-[16px] font-bold tracking-tight">
                {@sscc.code}
              </span>
            </div>
            <.label_field
              id="sscc-label-quantity"
              label="QUANTITY"
              value={@sscc.count_of_trade_items}
              align="right"
            />
          </div>
          <div class="mb-3 flex items-start">
            <.label_field
              label="CONTENT"
              value={@sscc.gtin && String.pad_leading(@sscc.gtin, 14, "0")}
            />
            <.label_field label="EXPIRY" value={long_date(@sscc.expiry_date)} align="right" />
          </div>
          <div class="mb-3 flex items-start">
            <.label_field label="BATCH/LOT" value={@sscc.batch} />
            <.label_field
              label="PROD DATE"
              value={long_date(@sscc.production_date)}
              align="right"
            />
          </div>
          <div class="mb-3 flex items-start border-b-2 border-black pb-2">
            <.label_field
              id="sscc-label-order-number"
              label="ORDER NUMBER"
              value={@sscc.order_number}
            />
          </div>

          <div class="flex items-start gap-4 pb-3 pl-6 pt-1">
            <canvas
              id={"sscc-barcode-#{@sscc.id}"}
              phx-hook="DataMatrix"
              phx-update="ignore"
              data-gs1-text={gs1_text(@sscc)}
              class="size-[120px] shrink-0"
            ></canvas>
            <div class="mt-2 flex-1 text-[12px] leading-[1.3]">
              <div :for={{ai, value} <- ai_elements(@sscc)}>({ai}) {value}</div>
            </div>
          </div>
        </div>
      </div>

      <div class="no-print td-header-actions">
        <.td_button
          id="print-manufacturer-label"
          type="button"
          variant="secondary"
          label="Print"
          phx-hook="LabelPrint"
          data-print-target={"#sscc-label-content-#{@sscc.id}"}
        />
        <.td_button
          id="download-manufacturer-label-svg"
          type="button"
          variant="secondary"
          label="Download SVG"
          phx-hook="LabelSvgDownload"
          data-role="download-label-svg"
          data-sscc={@sscc.code}
          data-gs1-text={gs1_text(@sscc)}
          data-gtin={@sscc.gtin}
          data-batch={@sscc.batch}
          data-production={@sscc.production_date}
          data-expiry={@sscc.expiry_date}
        />
      </div>
    </Layouts.manufacturer_shell>
    """
  end
end
