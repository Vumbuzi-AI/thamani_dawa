defmodule ThamaniDawaWeb.ManufacturerSsccLive.Serials do
  @moduledoc """
  Paginated list of primary serials packed under a shipper SSCC. The serials
  are fetched from the GS1 member API (`get_sscc_contents`), not the local
  database.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing

  @per_page 100

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    sscc = Manufacturing.get_sscc_group!(organization_id, id)

    {:ok,
     socket
     |> assign(:page_title, "Serials")
     |> assign(:sscc, sscc)
     |> assign(:serials, [])
     |> assign(:page, 1)
     |> assign(:per_page, @per_page)
     |> load_serials()}
  end

  def handle_params(params, _url, socket) do
    fallback =
      if gtin = socket.assigns.sscc.gtin,
        do: ~p"/manufacturer/products/#{gtin}/ssccs",
        else: ~p"/manufacturer/products"

    {:noreply, assign(socket, :back_path, ThamaniDawaWeb.ReturnTo.path(params, fallback))}
  end

  defp load_serials(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    code = socket.assigns.sscc.code

    assign_async(socket, :remote_serials, fn ->
      case Manufacturing.fetch_sscc_serials(organization_id, code) do
        {:ok, serials} -> {:ok, %{remote_serials: serials}}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  def handle_event("retry", _params, socket) do
    {:noreply, socket |> assign(:page, 1) |> load_serials()}
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

  defp gs1_text(serial) do
    "(01)#{gtin14(serial)}(10)#{serial.batch || ""}(11)#{date_ai(serial.production_date)}(17)#{date_ai(serial.expiry_date)}(21)#{serial.serial}"
  end

  defp gtin14(serial), do: String.pad_leading(serial.gtin || "", 14, "0")

  defp dom_key(serial),
    do:
      "#{gtin14(serial)}-#{serial.batch}-#{serial.serial}"
      |> String.replace(~r/[^A-Za-z0-9_-]/, "_")

  defp error_message(:not_found), do: "GS1 has no record of this SSCC yet."

  defp error_message(:unconfigured),
    do: "Add your GS1 API key in organization settings to load serials."

  defp error_message(reason) when reason in [:unauthorized, :forbidden],
    do: "GS1 rejected your API key."

  defp error_message(_reason), do: "Couldn't reach GS1 to load serials. Try again shortly."

  defp date_ai(nil), do: ""
  defp date_ai(date), do: Calendar.strftime(date, "%y%m%d")

  def render(assigns) do
    serials =
      if assigns.remote_serials.ok?, do: assigns.remote_serials.result, else: []

    assigns =
      assigns
      |> assign(:serials, serials)
      |> assign(:page_serials, page_slice(serials, assigns.page))

    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/products"}
    >
      <.td_back_link
        id="sscc-serials-back"
        to={@back_path}
        label={ThamaniDawaWeb.ReturnTo.label(@back_path, "Back to shipper SSCCs")}
      />
      <div class="td-idh">
        <div>
          <h1 class="td-idh-title font-mono">{@sscc.code}</h1>
          <p class="td-idh-sub">
            Shipper SSCC<span :if={@sscc.batch}> · Batch <span class="font-mono">{@sscc.batch}</span></span>
            <span :if={@remote_serials.ok?}> · {length(@serials)} serials</span>
          </p>
        </div>
        <div class="td-idh-actions">
          <.td_button
            id="sscc-serials-print-label"
            variant="primary"
            glyph="printer"
            label="Print label"
            navigate={~p"/manufacturer/sscc/#{@sscc.id}/label"}
          />
        </div>
      </div>

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
        <div
          :if={@remote_serials.loading}
          id="sscc-serials-loading"
          class="flex items-center gap-2 p-8 text-sm text-thamani-pewter"
        >
          <.icon name="hero-arrow-path" class="size-4 animate-spin" /> Loading serials from GS1…
        </div>
        <div
          :if={@remote_serials.failed}
          id="sscc-serials-error"
          class="flex flex-wrap items-center justify-between gap-3 p-8 text-sm text-red-700"
        >
          <span>{error_message(elem(@remote_serials.failed, 1))}</span>
          <.button id="retry-sscc-serials" type="button" phx-click="retry">Retry</.button>
        </div>
        <div
          :if={@remote_serials.ok? and @serials == []}
          id="sscc-serials-empty"
          class="p-8 text-sm text-thamani-pewter"
        >
          GS1 reports no serials packed under this SSCC.
        </div>
        <div
          :if={@remote_serials.ok? and @serials != []}
          id="sscc-serials"
          class="grid gap-4 p-5 sm:grid-cols-2 xl:grid-cols-3"
        >
          <article
            :for={serial <- @page_serials}
            id={"sscc-primary-#{dom_key(serial)}"}
            class="rounded-xl border border-thamani-lime/60 bg-thamani-lime/10 p-4"
          >
            <div id={"sscc-primary-label-#{dom_key(serial)}"} class="printable-primary-label">
              <p class="truncate font-mono text-sm font-semibold text-thamani-forest">
                {serial.serial}
              </p>
              <p class="mt-0.5 text-xs text-thamani-pewter">serial</p>
              <div class="mt-3 flex items-center gap-3">
                <canvas
                  id={"sscc-serial-datamatrix-#{dom_key(serial)}"}
                  phx-hook="DataMatrix"
                  phx-update="ignore"
                  data-gs1-text={gs1_text(serial)}
                  class="size-28 shrink-0 bg-white p-1"
                ></canvas>
                <dl class="min-w-0 text-xs leading-5 text-thamani-forest">
                  <div>(01) {gtin14(serial)}</div><div>
                    (10) {serial.batch}
                  </div><div>(17) {date_ai(serial.expiry_date)}</div><div>
                    (11) {date_ai(serial.production_date)}
                  </div><div class="truncate">(21) {serial.serial}</div>
                </dl>
              </div>
            </div>
            <div class="mt-4 flex flex-wrap gap-2">
              <button
                id={"print-sscc-serial-#{dom_key(serial)}"}
                type="button"
                phx-hook="LabelPrint"
                data-print-target={"#sscc-primary-label-#{dom_key(serial)}"}
                class="inline-flex items-center gap-1.5 rounded-lg bg-thamani-forest px-3 py-2 text-xs font-semibold text-white transition hover:bg-thamani-forest/90"
              ><.icon name="hero-printer" class="size-4" /> Print</button>
              <button
                id={"download-sscc-serial-#{dom_key(serial)}"}
                type="button"
                phx-hook="LabelSvgDownload"
                data-role="download-serial-svg"
                data-serial={serial.serial}
                data-gs1-text={gs1_text(serial)}
                data-gtin={serial.gtin}
                data-batch={serial.batch}
                class="inline-flex items-center gap-1.5 rounded-lg bg-emerald-600 px-3 py-2 text-xs font-semibold text-white transition hover:bg-emerald-700"
              ><.icon name="hero-arrow-down-tray" class="size-4" /> Download as SVG</button>
            </div>
          </article>
        </div>
      </section>

      <div :if={@remote_serials.ok? and @serials != []} class="mt-4 flex items-center justify-between">
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
