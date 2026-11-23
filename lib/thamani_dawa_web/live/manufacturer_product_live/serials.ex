defmodule ThamaniDawaWeb.ManufacturerProductLive.Serials do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing
  alias ThamaniDawaWeb.DistributorPagination

  def mount(%{"gtin" => gtin}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    product = Manufacturing.get_product_by_gtin!(organization_id, gtin)

    {:ok,
     socket
     |> assign(:page_title, "Product serials")
     |> assign(:product, product)
     |> assign(:search, "")}
  end

  def handle_params(params, _url, socket) do
    search = Map.get(params, "search", "")

    batches =
      Manufacturing.list_batches_for_serials(org_id(socket), socket.assigns.product.id, search)

    selected_batch = selected_batch(batches, Map.get(params, "batch"))
    page = DistributorPagination.page_number(params)

    serial_page =
      if selected_batch do
        Manufacturing.paginate_serials(org_id(socket), selected_batch.id,
          page: page,
          page_size: 24,
          search: search
        )
      end

    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:batches, batches)
     |> assign(:selected_batch, selected_batch)
     |> assign(:serial_page, serial_page)}
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/manufacturer/products/#{socket.assigns.product.gtin}/serials?#{%{search: search}}"
     )}
  end

  def handle_event("reset", _params, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/manufacturer/products/#{socket.assigns.product.gtin}/serials")}
  end

  defp org_id(socket), do: socket.assigns.current_scope.organization_id

  defp selected_batch([], _id), do: nil

  defp selected_batch(batches, id) do
    Enum.find_value(batches, fn {batch, _count} ->
      if to_string(batch.id) == id, do: batch
    end) || elem(hd(batches), 0)
  end

  defp gs1_text(product, batch, serial) do
    "(01)#{String.pad_leading(product.gtin, 14, "0")}(10)#{batch.batch_no}(11)#{date_ai(batch.production_date)}(17)#{date_ai(batch.expiry_date)}(21)#{serial.serial}"
  end

  defp date_ai(date), do: Calendar.strftime(date, "%y%m%d")

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/products"}
    >
      <.header icon="hero-qr-code">
        Primary serials
        <:subtitle>{@product.name} · <span class="font-mono">{@product.gtin}</span></:subtitle>
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
          <.blank_state :if={@batches == []} icon="hero-cube" title="No serials yet">
            Use + Serial on the Products page to create the first batch.
          </.blank_state>
          <.link
            :for={{batch, count} <- @batches}
            id={"serial-batch-#{batch.id}"}
            patch={
              ~p"/manufacturer/products/#{@product.gtin}/serials?#{%{batch: batch.id, search: @search}}"
            }
            class={[
              "block rounded-2xl border p-4 transition",
              @selected_batch && @selected_batch.id == batch.id &&
                "border-thamani-forest bg-thamani-mist",
              (!@selected_batch || @selected_batch.id != batch.id) &&
                "border-thamani-stone bg-white hover:border-thamani-sage"
            ]}
          >
            <div class="flex items-start justify-between gap-3">
              <span class="font-semibold text-thamani-forest">Batch {batch.batch_no}</span><span class="rounded-full bg-white px-2 py-1 text-xs font-bold text-thamani-forest">{count}</span>
            </div>
            <dl class="mt-3 space-y-1 text-xs text-thamani-pewter">
              <div class="flex justify-between">
                <dt>Produced</dt><dd>{batch.production_date}</dd>
              </div><div class="flex justify-between">
                <dt>Expires</dt><dd>{batch.expiry_date}</dd>
              </div>
            </dl>
          </.link>
        </aside>

        <section
          :if={@selected_batch}
          id="selected-serial-batch"
          class="rounded-2xl border border-thamani-stone bg-white p-5 shadow-sm"
        >
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <p class="text-xs font-bold uppercase tracking-[0.16em] text-thamani-pewter">Batch</p><h2 class="mt-1 text-xl font-semibold text-thamani-forest">
                {@selected_batch.batch_no}
              </h2><p class="mt-1 text-sm text-thamani-pewter">
                {@selected_batch.production_date} → {@selected_batch.expiry_date}
              </p>
            </div>
            <.button
              id="export-batch-serials"
              href={
                ~p"/manufacturer/products/#{@product.gtin}/batches/#{@selected_batch.id}/serials/export"
              }
            ><.icon name="hero-arrow-down-tray" class="size-4" /> Export CSV</.button>
          </div>

          <div id="manufacturer-serials" class="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
            <article
              :for={serial <- @serial_page.entries}
              id={"manufacturer-serial-#{serial.id}"}
              class="rounded-xl border border-thamani-stone bg-thamani-snow p-4"
            >
              <canvas
                id={"serial-datamatrix-#{serial.id}"}
                phx-hook="DataMatrix"
                phx-update="ignore"
                data-gs1-text={gs1_text(@product, @selected_batch, serial)}
                class="mx-auto size-32 bg-white"
              ></canvas>
              <p class="mt-3 truncate text-center font-mono text-xs text-thamani-forest">
                {serial.serial}
              </p>
              <button
                id={"download-serial-#{serial.id}"}
                type="button"
                phx-hook="LabelSvgDownload"
                data-role="download-serial-svg"
                data-serial={serial.serial}
                data-gs1-text={gs1_text(@product, @selected_batch, serial)}
                data-gtin={@product.gtin}
                data-batch={@selected_batch.batch_no}
                class="mt-3 flex w-full items-center justify-center gap-2 rounded-lg border border-thamani-stone bg-white px-3 py-2 text-xs font-semibold text-thamani-forest transition hover:bg-thamani-mist"
              ><.icon name="hero-arrow-down-tray" class="size-4" /> SVG</button>
            </article>
          </div>

          <.blank_state
            :if={@serial_page.total_entries == 0}
            icon="hero-magnifying-glass"
            title="No matching serials"
          >
            Try another serial or batch search.
          </.blank_state>
          <.pagination
            :if={@serial_page.total_entries > 0}
            page={@serial_page}
            path={
              ~p"/manufacturer/products/#{@product.gtin}/serials?#{%{batch: @selected_batch.id, search: @search}}"
            }
          />
        </section>
      </div>
    </Layouts.manufacturer_shell>
    """
  end
end
