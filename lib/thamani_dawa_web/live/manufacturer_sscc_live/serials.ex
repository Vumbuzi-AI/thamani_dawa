defmodule ThamaniDawaWeb.ManufacturerSsccLive.Serials do
  @moduledoc "Paginated list of primary serials packed under a shipper SSCC."

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing

  @per_page 100

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    sscc = Manufacturing.get_sscc_group!(organization_id, id)
    serials = Manufacturing.list_serials_for_sscc(organization_id, sscc.id)

    {:ok,
     socket
     |> assign(:page_title, "Serials")
     |> assign(:sscc, sscc)
     |> assign(:serials, serials)
     |> assign(:page, 1)
     |> assign(:per_page, @per_page)}
  end

  def handle_event("next_page", _params, socket) do
    {:noreply, assign(socket, :page, socket.assigns.page + 1)}
  end

  def handle_event("prev_page", _params, socket) do
    {:noreply, assign(socket, :page, max(socket.assigns.page - 1, 1))}
  end

  defp page_slice(serials, page) do
    serials |> Enum.drop((page - 1) * @per_page) |> Enum.take(@per_page)
  end

  defp gs1_text(sscc, serial) do
    "(01)#{String.pad_leading(sscc.gtin || "", 14, "0")}(10)#{sscc.batch || ""}(11)#{date_ai(sscc.production_date)}(17)#{date_ai(sscc.expiry_date)}(21)#{serial.serial}"
  end

  defp date_ai(nil), do: ""
  defp date_ai(date), do: Calendar.strftime(date, "%y%m%d")

  def render(assigns) do
    assigns = assign(assigns, :page_serials, page_slice(assigns.serials, assigns.page))

    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/products"}
    >
      <.header icon="hero-qr-code">
        Primary serials
        <:subtitle>
          <span class="font-mono">{@sscc.code}</span> · {length(@serials)} total
        </:subtitle>
      </.header>

      <section class="mt-6 overflow-hidden rounded-2xl border border-thamani-stone bg-white shadow-sm">
        <div class="flex flex-wrap items-center justify-between gap-3 border-b border-thamani-stone bg-thamani-snow px-5 py-4">
          <div class="flex items-center gap-3">
            <span class="flex size-10 items-center justify-center rounded-xl bg-thamani-lime/35 text-thamani-forest"><.icon
              name="hero-qr-code"
              class="size-5"
            /></span><div>
              <p class="text-xs font-bold uppercase tracking-[0.16em] text-thamani-pewter">
                Primary serials
              </p><p class="font-mono text-sm font-semibold text-thamani-forest">SSCC {@sscc.code}</p>
            </div>
          </div>
          <span class="rounded-full bg-white px-3 py-1.5 text-xs font-bold text-thamani-forest">{length(
            @serials
          )} items</span>
        </div>
        <div class="grid gap-4 p-5 sm:grid-cols-2 xl:grid-cols-3">
          <article
            :for={serial <- @page_serials}
            id={"sscc-primary-#{serial.id}"}
            class="rounded-xl border border-thamani-lime/60 bg-thamani-lime/10 p-4"
          >
            <p class="truncate font-mono text-sm font-semibold text-thamani-forest">
              {serial.serial}
            </p>
            <p class="mt-0.5 text-xs text-thamani-pewter">serial</p>
            <div class="mt-3 flex items-center gap-3">
              <canvas
                id={"sscc-serial-datamatrix-#{serial.id}"}
                phx-hook="DataMatrix"
                phx-update="ignore"
                data-gs1-text={gs1_text(@sscc, serial)}
                class="size-28 shrink-0 bg-white p-1"
              ></canvas>
              <dl class="min-w-0 text-xs leading-5 text-thamani-forest">
                <div>(01) {String.pad_leading(@sscc.gtin || "", 14, "0")}</div><div>
                  (10) {@sscc.batch}
                </div><div>(17) {date_ai(@sscc.expiry_date)}</div><div>
                  (11) {date_ai(@sscc.production_date)}
                </div><div class="truncate">(21) {serial.serial}</div>
              </dl>
            </div>
            <div class="mt-4 flex flex-wrap gap-2">
              <button
                id={"print-sscc-serial-#{serial.id}"}
                type="button"
                phx-hook="LabelPrint"
                data-print-target={"#sscc-primary-#{serial.id}"}
                class="inline-flex items-center gap-1.5 rounded-lg bg-thamani-forest px-3 py-2 text-xs font-semibold text-white transition hover:bg-thamani-forest/90"
              ><.icon name="hero-printer" class="size-4" /> Print</button>
              <button
                id={"download-sscc-serial-#{serial.id}"}
                type="button"
                phx-hook="LabelSvgDownload"
                data-role="download-serial-svg"
                data-serial={serial.serial}
                data-gs1-text={gs1_text(@sscc, serial)}
                data-gtin={@sscc.gtin}
                data-batch={@sscc.batch}
                class="inline-flex items-center gap-1.5 rounded-lg bg-emerald-600 px-3 py-2 text-xs font-semibold text-white transition hover:bg-emerald-700"
              ><.icon name="hero-arrow-down-tray" class="size-4" /> Download as SVG</button>
            </div>
          </article>
        </div>
      </section>

      <div class="mt-4 flex items-center justify-between">
        <.button type="button" phx-click="prev_page" disabled={@page == 1}>Previous</.button>
        <span class="text-xs text-thamani-pewter">Page {@page}</span>
        <.button type="button" phx-click="next_page" disabled={length(@page_serials) < @per_page}>
          Next
        </.button>
      </div>
    </Layouts.manufacturer_shell>
    """
  end
end
