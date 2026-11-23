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
    sscc = Manufacturing.get_sscc_group!(organization_id, id)

    {:ok,
     socket
     |> assign(:page_title, "SSCC label")
     |> assign(:sscc, sscc)}
  end

  defp gs1_text(sscc), do: Manufacturing.sscc_gs1_text(sscc)

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/products"}
    >
      <.header icon="hero-cube-transparent">
        SSCC label
        <:subtitle><span class="font-mono">{@sscc.code}</span></:subtitle>
      </.header>

      <div
        id={"sscc-label-content-#{@sscc.id}"}
        class="printable-sscc-label mt-6 box-border flex h-[6in] w-[4in] flex-col overflow-hidden border-2 border-black bg-white text-black"
        style="font-family: Arial, Helvetica, sans-serif"
      >
        <div class="grid grid-cols-2 border-b-2 border-black">
          <div class="border-r-2 border-black px-2.5 py-2.5">
            <p class="text-[15px] font-bold leading-tight">From</p>
            <p class="mt-1 text-[13px] leading-snug">
              {(@sscc.pallet && @sscc.pallet.from_company_name) || @sscc.from_company_name}
            </p>
            <p class="text-[13px] leading-snug">
              {(@sscc.pallet && @sscc.pallet.from_address) || @sscc.from_address}
            </p>
          </div>
          <div class="px-2.5 py-2.5">
            <p class="text-[15px] font-bold leading-tight">To</p>
            <p class="mt-1 text-[13px] leading-snug">
              {(@sscc.pallet && @sscc.pallet.to_company_name) || @sscc.to_company_name}
            </p>
            <p class="text-[13px] leading-snug">
              {(@sscc.pallet && @sscc.pallet.to_address) || @sscc.to_address}
            </p>
          </div>
        </div>

        <div class="flex min-h-0 flex-1 flex-col px-2.5 py-3">
          <div class="grid grid-cols-2 gap-x-4 gap-y-3.5 text-[13px]">
            <p><span class="font-semibold">GTIN</span><br />{@sscc.gtin}</p>
            <p class="text-right"><span class="font-semibold">BATCH</span><br />{@sscc.batch}</p>
            <p>
              <span class="font-semibold">PRODUCED</span><br />
              {@sscc.production_date && Calendar.strftime(@sscc.production_date, "%d %b %Y")}
            </p>
            <p class="text-right">
              <span class="font-semibold">EXPIRES</span><br />
              {@sscc.expiry_date && Calendar.strftime(@sscc.expiry_date, "%d %b %Y")}
            </p>
          </div>

          <div class="mt-auto border-t-2 border-black pt-3">
            <div class="flex items-start gap-3">
              <canvas
                id={"sscc-barcode-#{@sscc.id}"}
                phx-hook="DataMatrix"
                phx-update="ignore"
                data-gs1-text={gs1_text(@sscc)}
                class="size-[1.35in] shrink-0"
              ></canvas>
              <p class="pt-0.5 text-[11px] leading-[1.45] text-black">(00) {@sscc.code}</p>
            </div>
          </div>
        </div>
      </div>

      <div class="no-print mt-4 flex flex-wrap gap-2">
        <.button
          id="print-manufacturer-label"
          type="button"
          phx-hook="LabelPrint"
          data-print-target={"#sscc-label-content-#{@sscc.id}"}
        >
          <.icon name="hero-printer" class="size-4" /> Print
        </.button>
        <.button
          id="download-manufacturer-label-svg"
          type="button"
          phx-hook="LabelSvgDownload"
          data-role="download-label-svg"
          data-sscc={@sscc.code}
          data-gs1-text={gs1_text(@sscc)}
          data-gtin={@sscc.gtin}
          data-batch={@sscc.batch}
          data-production={@sscc.production_date}
          data-expiry={@sscc.expiry_date}
        >
          <.icon name="hero-arrow-down-tray" class="size-4" /> Download SVG
        </.button>
      </div>
    </Layouts.manufacturer_shell>
    """
  end
end
