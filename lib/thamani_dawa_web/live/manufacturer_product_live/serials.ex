defmodule ThamaniDawaWeb.ManufacturerProductLive.Serials do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing
  alias ThamaniDawaWeb.DistributorPagination

  @page_size 24

  def mount(%{"gtin" => gtin}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    product = Manufacturing.get_product_by_gtin!(organization_id, gtin)

    {:ok,
     socket
     |> assign(:page_title, "Product serials")
     |> assign(:product, product)
     |> assign(:search, "")
     |> assign(:batches, nil)
     |> assign(:batches_error, nil)
     |> assign(:selected_batch, nil)
     |> assign(:serials_cache, %{})
     |> assign(:serials_error, nil)
     |> assign(:serial_page, nil)}
  end

  # Nested GS1 flow, kept light on the API: the batch list is fetched once
  # per visit (`getbarcode_batches`), and a batch's serials only when that
  # batch is opened (`get_batch_serials`), then cached for this visit so
  # paging and searching don't call GS1 again. Nothing is fetched on the
  # static (disconnected) render.
  def handle_params(params, _url, socket) do
    search = Map.get(params, "search", "")

    socket =
      socket
      |> assign(:search, search)
      |> ensure_batches()

    {:noreply, select_batch(socket, Map.get(params, "batch"), search, params)}
  end

  defp ensure_batches(%{assigns: %{batches: nil}} = socket) do
    if connected?(socket) do
      case Manufacturing.fetch_product_batches(org_id(socket), socket.assigns.product.gtin) do
        {:ok, batches} -> assign(socket, batches: batches, batches_error: nil)
        {:error, reason} -> assign(socket, batches: [], batches_error: reason)
      end
    else
      socket
    end
  end

  defp ensure_batches(socket), do: socket

  defp select_batch(%{assigns: %{batches: nil}} = socket, _batch_no, _search, _params),
    do: socket

  defp select_batch(socket, batch_no, search, params) do
    visible = filter_batches(socket.assigns.batches, search)
    selected = Enum.find(visible, &(&1.batch_no == batch_no)) || List.first(visible)

    case selected do
      nil ->
        assign(socket, selected_batch: nil, serial_page: nil, serials_error: nil)

      batch ->
        {socket, result} = batch_serials(socket, batch.batch_no)

        case result do
          {:ok, serials} ->
            serials = filter_serials(serials, search, batch)

            page =
              DistributorPagination.page(
                serials,
                DistributorPagination.page_number(params),
                @page_size
              )

            assign(socket, selected_batch: batch, serial_page: page, serials_error: nil)

          {:error, reason} ->
            assign(socket, selected_batch: batch, serial_page: nil, serials_error: reason)
        end
    end
  end

  defp batch_serials(socket, batch_no) do
    case socket.assigns.serials_cache do
      %{^batch_no => serials} ->
        {socket, {:ok, serials}}

      cache ->
        case Manufacturing.fetch_batch_serials(
               org_id(socket),
               socket.assigns.product.gtin,
               batch_no
             ) do
          {:ok, serials} ->
            {assign(socket, :serials_cache, Map.put(cache, batch_no, serials)), {:ok, serials}}

          error ->
            {socket, error}
        end
    end
  end

  # A search matching the batch number shows the whole batch; otherwise it
  # narrows the batch's serials.
  # Narrow to batches whose number matches; when none do, the term is
  # treated as a serial and searched within the selected batch.
  defp filter_batches(batches, search) do
    term = search |> String.trim() |> String.downcase()

    matching =
      if term == "",
        do: batches,
        else: Enum.filter(batches, &String.contains?(String.downcase(&1.batch_no), term))

    if matching == [], do: batches, else: matching
  end

  defp filter_serials(serials, "", _batch), do: serials

  defp filter_serials(serials, search, batch) do
    term = String.downcase(String.trim(search))

    if term == "" or String.contains?(String.downcase(batch.batch_no), term),
      do: serials,
      else: Enum.filter(serials, &String.contains?(String.downcase(&1.serial), term))
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/manufacturer/products/#{socket.assigns.product.gtin}/serials?#{search_params(socket, search)}"
     )}
  end

  def handle_event("reset", _params, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/manufacturer/products/#{socket.assigns.product.gtin}/serials")}
  end

  def handle_event("retry", _params, socket) do
    {:noreply,
     socket
     |> assign(batches: nil, serials_cache: %{})
     |> push_patch(to: ~p"/manufacturer/products/#{socket.assigns.product.gtin}/serials")}
  end

  defp search_params(socket, search) do
    case socket.assigns.selected_batch do
      nil -> %{search: search}
      batch -> %{batch: batch.batch_no, search: search}
    end
  end

  defp org_id(socket), do: socket.assigns.current_scope.organization_id

  defp gtin14(product), do: String.pad_leading(product.gtin, 14, "0")

  defp gs1_text(product, batch, serial) do
    "(01)#{gtin14(product)}(10)#{batch.batch_no}(11)#{date_ai(batch.production_date)}(17)#{date_ai(batch.expiry_date)}(21)#{serial.serial}"
  end

  defp dom_key(value), do: String.replace(value, ~r/[^A-Za-z0-9_-]/, "_")

  defp date_ai(nil), do: ""
  defp date_ai(date), do: Calendar.strftime(date, "%y%m%d")

  defp long_date(nil), do: "—"
  defp long_date(date), do: Calendar.strftime(date, "%d %b %Y")

  defp error_message(:unconfigured),
    do: "Add your GS1 API key in organization settings to load serials."

  defp error_message(reason) when reason in [:unauthorized, :forbidden],
    do: "GS1 rejected your API key."

  defp error_message({:invalid, message}), do: message
  defp error_message(_reason), do: "Couldn't reach GS1 to load serials. Try again shortly."

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/products"}
    >
      <.header icon="hero-qr-code">
        Primary serials
        <:subtitle>{@product.name} · {@product.gtin}</:subtitle>
        <:actions>
          <.button navigate={~p"/manufacturer/products"}><.icon name="hero-arrow-left" class="size-4" />
          Products</.button>
        </:actions>
      </.header>

      <div class="mt-6 flex gap-3 rounded-2xl border border-thamani-stone bg-white p-3">
        <form id="manufacturer-serial-search" phx-change="search" class="flex-1">
          <.input
            type="search"
            name="search"
            value={@search}
            placeholder="Search serial or batch"
            phx-debounce="300"
            class="w-full"
          />
        </form>
        <.button id="reset-manufacturer-serial-search" type="button" phx-click="reset">Reset</.button>
      </div>

      <div id="manufacturer-serial-batches" class="mt-5 grid gap-4 lg:grid-cols-[18rem_1fr]">
        <aside class="space-y-3">
          <div
            :if={is_nil(@batches)}
            id="serial-batches-loading"
            class="flex items-center gap-2 rounded-2xl border border-thamani-stone bg-white p-4 text-sm text-thamani-pewter"
          >
            <.icon name="hero-arrow-path" class="size-4 animate-spin" /> Loading batches from GS1…
          </div>
          <div
            :if={@batches_error}
            id="serial-batches-error"
            class="space-y-3 rounded-2xl border border-red-200 bg-red-50 p-4 text-sm text-red-700"
          >
            <p>{error_message(@batches_error)}</p>
            <.button id="retry-serial-batches" type="button" phx-click="retry">Retry</.button>
          </div>
          <.blank_state
            :if={@batches == [] and is_nil(@batches_error)}
            icon="hero-cube"
            title="No serials yet"
          >
            Use + Serial on the Products page to create the first batch.
          </.blank_state>
          <.link
            :for={batch <- @batches || []}
            id={"serial-batch-#{dom_key(batch.batch_no)}"}
            patch={
              ~p"/manufacturer/products/#{@product.gtin}/serials?#{%{batch: batch.batch_no, search: @search}}"
            }
            class={[
              "block rounded-2xl border p-4 transition",
              @selected_batch && @selected_batch.batch_no == batch.batch_no &&
                "border-thamani-forest bg-thamani-mist",
              (!@selected_batch || @selected_batch.batch_no != batch.batch_no) &&
                "border-thamani-stone bg-white hover:border-thamani-sage"
            ]}
          >
            <div class="flex items-start justify-between gap-3">
              <span class="font-semibold text-thamani-forest">Batch {batch.batch_no}</span><span class="rounded-full bg-white px-2 py-1 text-xs font-bold text-thamani-forest">{batch.serial_count}</span>
            </div>
            <dl class="mt-3 space-y-1 text-xs text-thamani-pewter">
              <div class="flex justify-between">
                <dt>Produced</dt><dd>{long_date(batch.production_date)}</dd>
              </div><div class="flex justify-between">
                <dt>Expires</dt><dd>{long_date(batch.expiry_date)}</dd>
              </div>
            </dl>
          </.link>
        </aside>

        <section
          :if={@selected_batch}
          id="selected-serial-batch"
          class="overflow-hidden rounded-2xl border border-thamani-stone bg-white shadow-sm"
        >
          <div class="flex flex-wrap items-center justify-between gap-4 border-b border-thamani-stone bg-thamani-snow px-5 py-4 sm:px-6">
            <div class="flex items-center gap-3">
              <span class="flex size-10 items-center justify-center rounded-xl bg-thamani-lime/45 text-thamani-forest shadow-sm">
                <.icon name="hero-qr-code" class="size-5" />
              </span>
              <div>
                <p class="text-xs font-bold uppercase tracking-[0.16em] text-thamani-pewter">
                  Primary serial batch
                </p>
                <h2 class="mt-0.5 text-lg font-semibold tracking-tight text-thamani-forest">
                  Batch {@selected_batch.batch_no}
                </h2>
              </div>
            </div>
            <.button
              id="export-batch-serials"
              href={
                ~p"/manufacturer/products/#{@product.gtin}/batches/#{@selected_batch.batch_no}/serials/export"
              }
            ><.icon name="hero-arrow-down-tray" class="size-4" /> Export CSV</.button>
          </div>

          <dl
            id="primary-serial-batch-details"
            class="grid divide-y divide-thamani-stone sm:grid-cols-2 sm:divide-x sm:divide-y-0 xl:grid-cols-4"
          >
            <div id="primary-serial-gtin" class="px-5 py-4 sm:px-6">
              <dt class="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.12em] text-thamani-pewter">
                <.icon name="hero-barcode" class="size-4 text-thamani-forest" /> GTIN
              </dt>
              <dd class="mt-2 font-mono text-sm font-semibold text-thamani-forest">
                {@product.gtin}
              </dd>
            </div>
            <div id="primary-serial-batch-number" class="px-5 py-4 sm:px-6">
              <dt class="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.12em] text-thamani-pewter">
                <.icon name="hero-tag" class="size-4 text-thamani-forest" /> Batch number
              </dt>
              <dd class="mt-2 font-mono text-sm font-semibold text-thamani-forest">
                {@selected_batch.batch_no}
              </dd>
            </div>
            <div id="primary-serial-production-date" class="px-5 py-4 sm:px-6">
              <dt class="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.12em] text-thamani-pewter">
                <.icon name="hero-calendar-days" class="size-4 text-thamani-forest" /> Production date
              </dt>
              <dd class="mt-2 text-sm font-semibold text-thamani-forest">
                {long_date(@selected_batch.production_date)}
              </dd>
            </div>
            <div id="primary-serial-expiry-date" class="px-5 py-4 sm:px-6">
              <dt class="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.12em] text-thamani-pewter">
                <.icon name="hero-calendar-days" class="size-4 text-thamani-forest" /> Expiry date
              </dt>
              <dd class="mt-2 text-sm font-semibold text-thamani-forest">
                {long_date(@selected_batch.expiry_date)}
              </dd>
            </div>
          </dl>

          <div
            :if={@serials_error}
            id="manufacturer-serials-error"
            class="m-5 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700 sm:m-6"
          >
            <span>{error_message(@serials_error)}</span>
            <.button id="retry-manufacturer-serials" type="button" phx-click="retry">Retry</.button>
          </div>

          <div
            :if={@serial_page}
            id="manufacturer-serials"
            class="m-5 grid gap-4 sm:m-6 sm:grid-cols-2 xl:grid-cols-3"
          >
            <article
              :for={serial <- @serial_page.entries}
              id={"manufacturer-serial-#{dom_key(serial.serial)}"}
              class="rounded-xl border border-thamani-lime/60 bg-thamani-lime/10 p-4 transition hover:shadow-sm"
            >
              <p class="truncate font-mono text-sm font-semibold text-thamani-forest">
                {serial.serial}
              </p>
              <p class="mt-0.5 text-xs text-thamani-pewter">serial</p>
              <div class="mt-3 flex items-center gap-3">
                <canvas
                  id={"serial-datamatrix-#{dom_key(serial.serial)}"}
                  phx-hook="DataMatrix"
                  phx-update="ignore"
                  data-gs1-text={gs1_text(@product, @selected_batch, serial)}
                  class="size-28 shrink-0 bg-white p-1"
                ></canvas>
                <dl class="min-w-0 text-xs leading-5 text-thamani-forest">
                  <div>(01) {gtin14(@product)}</div>
                  <div>(10) {@selected_batch.batch_no}</div>
                  <div>(17) {date_ai(@selected_batch.expiry_date)}</div>
                  <div>(11) {date_ai(@selected_batch.production_date)}</div>
                  <div class="truncate">(21) {serial.serial}</div>
                </dl>
              </div>
              <div class="mt-4 flex flex-wrap gap-2">
                <button
                  id={"print-serial-#{dom_key(serial.serial)}"}
                  type="button"
                  phx-hook="LabelPrint"
                  data-print-target={"#manufacturer-serial-#{dom_key(serial.serial)}"}
                  class="inline-flex items-center gap-1.5 rounded-lg bg-thamani-forest px-3 py-2 text-xs font-semibold text-white transition hover:bg-thamani-forest/90"
                ><.icon name="hero-printer" class="size-4" /> Print</button>
                <button
                  id={"download-serial-#{dom_key(serial.serial)}"}
                  type="button"
                  phx-hook="LabelSvgDownload"
                  data-role="download-serial-svg"
                  data-serial={serial.serial}
                  data-gs1-text={gs1_text(@product, @selected_batch, serial)}
                  data-gtin={@product.gtin}
                  data-batch={@selected_batch.batch_no}
                  class="inline-flex items-center gap-1.5 rounded-lg bg-emerald-600 px-3 py-2 text-xs font-semibold text-white transition hover:bg-emerald-700"
                ><.icon name="hero-arrow-down-tray" class="size-4" /> Download as SVG</button>
              </div>
            </article>
          </div>

          <.blank_state
            :if={@serial_page && @serial_page.total_entries == 0}
            class="mx-5 mb-5 sm:mx-6 sm:mb-6"
            icon="hero-magnifying-glass"
            title="No matching serials"
          >
            Try another serial or batch search.
          </.blank_state>
          <.pagination
            :if={@serial_page && @serial_page.total_entries > 0}
            page={@serial_page}
            path={
              ~p"/manufacturer/products/#{@product.gtin}/serials?#{%{batch: @selected_batch.batch_no, search: @search}}"
            }
          />
        </section>
      </div>
    </Layouts.manufacturer_shell>
    """
  end
end
