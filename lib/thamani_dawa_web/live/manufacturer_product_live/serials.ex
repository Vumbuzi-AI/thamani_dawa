defmodule ThamaniDawaWeb.ManufacturerProductLive.Serials do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Distributor.GlnLookup
  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Sites
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
     |> assign(:serial_page, nil)
     |> assign(:batch_shippers, [])
     |> assign(:serial_shippers, %{})
     |> reset_pack()}
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
        assign(socket,
          selected_batch: nil,
          serial_page: nil,
          serials_error: nil,
          batch_shippers: [],
          serial_shippers: %{}
        )

      batch ->
        {socket, result} = batch_serials(socket, batch.batch_no)

        {shippers, by_serial} =
          Manufacturing.list_batch_shippers(
            org_id(socket),
            socket.assigns.product.gtin,
            batch.batch_no
          )

        socket = assign(socket, batch_shippers: shippers, serial_shippers: by_serial)

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

  # Aggregation later: pack a batch's unpacked serials into a new shipper
  # SSCC. Unpacked serials are fetched (one `list_unpacked_serials` call)
  # only when the panel is opened, never on page load.
  def handle_event("open_pack", _params, socket) do
    %{product: product, selected_batch: batch} = socket.assigns

    case Manufacturing.fetch_unpacked_serials(org_id(socket), product.gtin, batch.batch_no) do
      {:ok, serials} ->
        facilities = Sites.list_sites(org_id(socket))
        from_gln = default_from_gln(socket, facilities)

        {:noreply,
         socket
         |> assign(:pack_open, true)
         |> assign(:pack_serials, serials)
         |> assign(:pack_selected, MapSet.new(serials))
         |> assign(:pack_facilities, Enum.filter(facilities, &(&1.gln not in [nil, ""])))
         |> assign(:pack_error, nil)
         |> assign(:pack_form, pack_form(%{"from_gln" => from_gln}))}

      {:error, reason} ->
        {:noreply, assign(socket, pack_open: true, pack_serials: [], pack_error: reason)}
    end
  end

  def handle_event("close_pack", _params, socket), do: {:noreply, reset_pack(socket)}

  def handle_event("toggle_pack_serial", %{"serial" => serial}, socket) do
    selected = socket.assigns.pack_selected

    selected =
      if MapSet.member?(selected, serial),
        do: MapSet.delete(selected, serial),
        else: MapSet.put(selected, serial)

    {:noreply, assign(socket, :pack_selected, selected)}
  end

  def handle_event("pack_select_all", _params, socket),
    do: {:noreply, assign(socket, :pack_selected, MapSet.new(socket.assigns.pack_serials))}

  def handle_event("pack_clear", _params, socket),
    do: {:noreply, assign(socket, :pack_selected, MapSet.new())}

  def handle_event("validate_pack", %{"pack" => params}, socket),
    do: {:noreply, assign(socket, :pack_form, pack_form(params))}

  # Destination GLN combobox backed by the GS1 GLN directory.
  def handle_event("search_pack_to_gln", %{"value" => query}, socket) do
    query = String.trim(query)
    form = pack_form(Map.put(socket.assigns.pack_form.params, "to_gln", ""))

    socket =
      socket
      |> assign(:pack_form, form)
      |> assign(:to_gln_query, query)
      |> assign(:to_gln_results, [])

    if String.length(query) < 2 do
      {:noreply, assign(socket, :to_gln_search_status, :idle)}
    else
      api_token = Organizations.gs1_api_key(org_id(socket))

      {:noreply,
       socket
       |> assign(:to_gln_search_status, :searching)
       |> start_async(:to_gln_search, fn ->
         {query, GlnLookup.search_destination(api_token, query)}
       end)}
    end
  end

  def handle_event("select_pack_to_gln", %{"gln" => gln}, socket) do
    case Enum.find(socket.assigns.to_gln_results, &(&1.gln == gln)) do
      nil ->
        {:noreply, put_flash(socket, :error, "That destination GLN is no longer available.")}

      party ->
        {:noreply,
         socket
         |> assign(:pack_form, pack_form(Map.put(socket.assigns.pack_form.params, "to_gln", gln)))
         |> assign(:to_gln_query, "#{party.gln} · #{party.company}")
         |> assign(:to_gln_results, [])
         |> assign(:to_gln_search_status, :selected)}
    end
  end

  def handle_event("submit_pack", %{"pack" => params}, socket) do
    %{product: product, selected_batch: batch, pack_serials: all, pack_selected: selected} =
      socket.assigns

    serials = Enum.filter(all, &MapSet.member?(selected, &1))

    case Manufacturing.pack_serials_into_shipper(
           org_id(socket),
           product,
           batch,
           serials,
           params,
           site_gln: current_site_gln(socket)
         ) do
      {:ok, shipper} ->
        {:noreply,
         socket
         |> reset_pack()
         |> put_flash(
           :info,
           "Shipper SSCC #{shipper.code} created with #{length(serials)} serials."
         )
         |> push_navigate(to: ~p"/manufacturer/sscc/#{shipper.id}/serials")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:pack_form, pack_form(params))
         |> assign(:pack_error, reason)}
    end
  end

  def handle_event("retry", _params, socket) do
    {:noreply,
     socket
     |> assign(batches: nil, serials_cache: %{})
     |> push_patch(to: ~p"/manufacturer/products/#{socket.assigns.product.gtin}/serials")}
  end

  def handle_async(:to_gln_search, {:ok, {query, {:ok, results}}}, socket) do
    if socket.assigns.to_gln_query == query do
      {:noreply,
       socket |> assign(:to_gln_results, results) |> assign(:to_gln_search_status, :complete)}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:to_gln_search, _result, socket) do
    {:noreply,
     socket |> assign(:to_gln_results, []) |> assign(:to_gln_search_status, :unavailable)}
  end

  defp reset_pack(socket) do
    socket
    |> assign(:to_gln_query, "")
    |> assign(:to_gln_results, [])
    |> assign(:to_gln_search_status, :idle)
    |> assign(:pack_open, false)
    |> assign(:pack_serials, [])
    |> assign(:pack_selected, MapSet.new())
    |> assign(:pack_facilities, [])
    |> assign(:pack_error, nil)
    |> assign(:pack_form, pack_form(%{}))
  end

  defp pack_form(params) do
    %{"from_gln" => "", "to_gln" => "", "order_number" => ""}
    |> Map.merge(params)
    |> to_form(as: :pack)
  end

  defp default_from_gln(socket, facilities) do
    current_site_gln(socket) ||
      Enum.find_value(facilities, &if(&1.gln not in [nil, ""], do: &1.gln))
  end

  defp current_site_gln(socket) do
    with id when not is_nil(id) <- socket.assigns.current_scope.current_site_id,
         %{gln: gln} when gln not in [nil, ""] <- Sites.get_site!(org_id(socket), id) do
      gln
    else
      _ -> nil
    end
  end

  defp facility_options(facilities),
    do: Enum.map(facilities, &{"#{&1.name} · #{&1.gln}", &1.gln})

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

      <div class="mt-6 flex gap-3 rounded-2xl border border-thamani-stone bg-td-surface p-3">
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
                "border-thamani-forest bg-td-wash",
              (!@selected_batch || @selected_batch.batch_no != batch.batch_no) &&
                "border-thamani-stone bg-td-surface hover:border-td-hairline"
            ]}
          >
            <div class="flex items-start justify-between gap-3">
              <span class="font-semibold text-thamani-forest">Batch {batch.batch_no}</span><span class="rounded-full bg-td-surface px-2 py-1 text-xs font-bold text-thamani-forest">{batch.serial_count}</span>
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
          class="overflow-hidden rounded-2xl border border-thamani-stone bg-td-surface shadow-sm"
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
            <div class="flex flex-wrap gap-2">
              <.button
                :if={!@pack_open}
                id="open-pack-serials"
                type="button"
                phx-click="open_pack"
                phx-disable-with="Loading unpacked serials…"
              ><.icon name="hero-archive-box-arrow-down" class="size-4" /> Create shipper SSCC</.button>
              <.button
                id="export-batch-serials"
                href={
                  ~p"/manufacturer/products/#{@product.gtin}/batches/#{@selected_batch.batch_no}/serials/export"
                }
              ><.icon name="hero-arrow-down-tray" class="size-4" /> Export CSV</.button>
            </div>
          </div>

          <section
            :if={@pack_open}
            id="pack-serials-panel"
            class="border-b border-thamani-stone bg-thamani-mist/40 px-5 py-5 sm:px-6"
          >
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div>
                <p class="text-xs font-bold uppercase tracking-[0.16em] text-thamani-pewter">
                  Aggregate later
                </p>
                <h3 class="mt-0.5 text-base font-semibold text-thamani-forest">
                  Pack unpacked serials into a shipper SSCC
                </h3>
                <p class="mt-1 text-xs text-thamani-pewter">
                  Batch {@selected_batch.batch_no} · {length(@pack_serials)} unpacked ·
                  <span id="pack-selected-count">{MapSet.size(@pack_selected)}</span>
                  selected
                </p>
              </div>
              <button
                id="close-pack-serials"
                type="button"
                phx-click="close_pack"
                class="rounded-lg p-1.5 text-thamani-pewter transition hover:bg-white hover:text-thamani-forest"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>

            <p
              :if={@pack_error}
              id="pack-serials-error"
              class="mt-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700"
            >
              {error_message(@pack_error)}
            </p>

            <p
              :if={@pack_serials == [] and is_nil(@pack_error)}
              id="pack-serials-empty"
              class="mt-4 rounded-xl border border-thamani-stone bg-white px-4 py-3 text-sm text-thamani-pewter"
            >
              Every serial in this batch is already packed into a shipper.
            </p>

            <.form
              :if={@pack_serials != []}
              for={@pack_form}
              id="pack-serials-form"
              phx-change="validate_pack"
              phx-submit="submit_pack"
              class="mt-4 space-y-4"
            >
              <div class="flex items-center gap-3 text-xs font-semibold">
                <button
                  id="pack-select-all"
                  type="button"
                  phx-click="pack_select_all"
                  class="text-thamani-forest underline-offset-2 hover:underline"
                >
                  Select all
                </button>
                <button
                  id="pack-clear"
                  type="button"
                  phx-click="pack_clear"
                  class="text-thamani-pewter underline-offset-2 hover:underline"
                >
                  Clear
                </button>
              </div>

              <div
                id="pack-serial-options"
                class="grid max-h-72 gap-2 overflow-y-auto rounded-xl border border-thamani-stone bg-white p-3 sm:grid-cols-2 xl:grid-cols-4"
              >
                <button
                  :for={serial <- @pack_serials}
                  id={"pack-serial-#{dom_key(serial)}"}
                  type="button"
                  phx-click="toggle_pack_serial"
                  phx-value-serial={serial}
                  class={[
                    "flex items-center gap-2 rounded-lg border px-3 py-2 text-left font-mono text-xs transition",
                    if(MapSet.member?(@pack_selected, serial),
                      do: "border-thamani-forest bg-thamani-lime/20 text-thamani-forest",
                      else: "border-thamani-stone text-thamani-pewter hover:border-thamani-sage"
                    )
                  ]}
                >
                  <.icon
                    name={
                      if(MapSet.member?(@pack_selected, serial),
                        do: "hero-check-circle-solid",
                        else: "hero-stop"
                      )
                    }
                    class="size-4 shrink-0"
                  />
                  <span class="truncate">{serial}</span>
                </button>
              </div>

              <div class="grid gap-4 sm:grid-cols-3">
                <.input
                  field={@pack_form[:from_gln]}
                  type="select"
                  label="From facility"
                  options={facility_options(@pack_facilities)}
                  prompt="Choose a facility"
                />
                <div class="space-y-1.5">
                  <label for="pack_to_gln_search" class="thamani-label">To GLN</label>
                  <input type="hidden" name="pack[to_gln]" value={@pack_form[:to_gln].value} />
                  <div id="pack-to-gln-combobox" class="relative">
                    <input
                      id="pack_to_gln_search"
                      type="search"
                      value={@to_gln_query}
                      phx-keyup="search_pack_to_gln"
                      phx-debounce="300"
                      autocomplete="off"
                      placeholder="Search by GLN, company, or address"
                      class="thamani-input w-full"
                    />
                    <div
                      :if={@to_gln_results != []}
                      id="pack-to-gln-results"
                      role="listbox"
                      class="absolute z-[70] mt-1 max-h-56 w-full overflow-y-auto rounded-xl border border-thamani-stone bg-white py-1 shadow-lg"
                    >
                      <button
                        :for={party <- @to_gln_results}
                        id={"pack-to-gln-#{party.gln}"}
                        type="button"
                        role="option"
                        phx-click="select_pack_to_gln"
                        phx-value-gln={party.gln}
                        class="block w-full px-3 py-2 text-left text-sm transition hover:bg-thamani-mist"
                      >
                        <span class="block font-mono font-semibold text-thamani-forest">
                          {party.gln}
                        </span>
                        <span class="block text-xs text-thamani-pewter">
                          {party.company} · {party.address || "—"}
                        </span>
                      </button>
                    </div>
                  </div>
                  <p :if={String.length(@to_gln_query) == 1} class="text-xs text-thamani-pewter">
                    Type at least 2 characters to search the GS1 GLN directory.
                  </p>
                  <p :if={@to_gln_search_status == :searching} class="text-xs text-thamani-pewter">
                    <.icon name="hero-arrow-path" class="inline size-3.5 motion-safe:animate-spin" />
                    Searching GS1 GLNs…
                  </p>
                  <p
                    :if={@to_gln_search_status == :complete and @to_gln_results == []}
                    class="rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800"
                  >
                    No GS1 GLNs match this search.
                  </p>
                  <p :if={@to_gln_search_status == :unavailable} class="text-xs text-red-700">
                    The GS1 GLN directory is unavailable. Try again in a moment.
                  </p>
                </div>
                <.input
                  field={@pack_form[:order_number]}
                  type="text"
                  label="Order number (optional)"
                />
              </div>

              <div class="flex justify-end">
                <.button
                  id="submit-pack-serials"
                  type="submit"
                  variant="primary"
                  disabled={MapSet.size(@pack_selected) == 0}
                  phx-disable-with="Creating shipper SSCC…"
                >
                  <.icon name="hero-archive-box" class="size-4" />
                  Create SSCC for {MapSet.size(@pack_selected)} serials
                </.button>
              </div>
            </.form>
          </section>

          <div
            :if={@batch_shippers != []}
            id="batch-shipper-ssccs"
            class="border-b border-thamani-stone px-5 py-5 sm:px-6"
          >
            <div class="flex items-center justify-between gap-3">
              <div>
                <p class="text-xs font-bold uppercase tracking-[0.16em] text-thamani-pewter">
                  Aggregation
                </p>
                <h3 class="mt-0.5 font-semibold text-thamani-forest">
                  Shipper SSCCs for batch {@selected_batch.batch_no}
                </h3>
              </div>
              <span class="rounded-full bg-thamani-mist px-3 py-1 text-xs font-bold text-thamani-forest">
                {length(@batch_shippers)} SSCCs
              </span>
            </div>
            <div class="mt-4 grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
              <article
                :for={shipper <- @batch_shippers}
                id={"batch-shipper-#{shipper.id}"}
                class="flex flex-col rounded-2xl border border-thamani-stone bg-white p-5 shadow-sm transition hover:-translate-y-0.5 hover:border-thamani-sage hover:shadow-md"
              >
                <div class="flex items-start gap-3">
                  <span class="flex size-10 flex-none items-center justify-center rounded-xl bg-thamani-lime/45 text-thamani-forest">
                    <.icon name="hero-qr-code" class="size-5" />
                  </span>
                  <div class="min-w-0 flex-1">
                    <p class="text-xs font-bold uppercase tracking-wide text-thamani-pewter">
                      Shipper SSCC
                    </p>
                    <p
                      class="truncate font-mono text-sm font-bold text-thamani-forest"
                      title={shipper.code}
                    >
                      {shipper.code}
                    </p>
                  </div>
                </div>
                <dl class="mt-5 grid grid-cols-2 gap-x-4 gap-y-4 text-sm">
                  <div>
                    <dt class="text-xs font-bold uppercase text-thamani-pewter/80">Batch</dt>
                    <dd class="mt-1 font-bold text-thamani-forest">{shipper.batch}</dd>
                  </div>
                  <div>
                    <dt class="text-xs font-bold uppercase text-thamani-pewter/80">GTIN</dt>
                    <dd class="mt-1 truncate font-mono text-thamani-forest">{shipper.gtin}</dd>
                  </div>
                  <div>
                    <dt class="text-xs font-bold uppercase text-thamani-pewter/80">To GLN</dt>
                    <dd class="mt-1 truncate font-mono text-thamani-forest">
                      {shipper.to_gln || "—"}
                    </dd>
                  </div>
                  <div>
                    <dt class="text-xs font-bold uppercase text-thamani-pewter/80">Packed</dt>
                    <dd class="mt-1 text-thamani-forest">
                      {Calendar.strftime(shipper.inserted_at, "%d %b %Y")}
                    </dd>
                  </div>
                </dl>
                <div class="mt-5 flex flex-wrap gap-2">
                  <span class="rounded-full bg-emerald-50 px-3 py-1.5 text-xs font-bold text-emerald-700">
                    {shipper.count_of_trade_items || 0} Primary serials
                  </span>
                </div>
                <hr class="my-5 border-thamani-stone" />
                <div class="mt-auto flex flex-wrap gap-2">
                  <.link
                    id={"batch-shipper-serials-#{shipper.id}"}
                    navigate={~p"/manufacturer/sscc/#{shipper.id}/serials"}
                    class="inline-flex items-center gap-1.5 rounded-full bg-thamani-forest px-3 py-1.5 text-xs font-semibold text-white transition hover:bg-thamani-forest/90"
                  >
                    <.icon name="hero-list-bullet" class="size-4" /> Serials
                  </.link>
                  <.link
                    id={"batch-shipper-label-#{shipper.id}"}
                    navigate={~p"/manufacturer/sscc/#{shipper.id}/label"}
                    class="inline-flex items-center gap-1.5 rounded-full border border-thamani-stone px-3 py-1.5 text-xs font-semibold text-thamani-forest transition hover:border-thamani-sage hover:bg-thamani-mist"
                  >
                    <.icon name="hero-qr-code" class="size-4" /> Shipper label
                  </.link>
                </div>
              </article>
            </div>
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
              class="rounded-xl border border-td-hairline bg-td-surface p-4 transition hover:shadow-sm"
            >
              <p class="truncate font-mono text-sm font-semibold text-thamani-forest">
                {serial.serial}
              </p>
              <div class="mt-0.5 flex items-center justify-between gap-2">
                <p class="text-xs text-thamani-pewter">serial</p>
                <%= case Map.get(@serial_shippers, serial.serial) do %>
                  <% nil -> %>
                    <span
                      id={"serial-unpacked-#{dom_key(serial.serial)}"}
                      class="rounded-full bg-td-surface px-2 py-0.5 text-[11px] font-semibold text-thamani-pewter"
                    >
                      Unpacked
                    </span>
                  <% shipper -> %>
                    <.link
                      id={"serial-sscc-#{dom_key(serial.serial)}"}
                      navigate={~p"/manufacturer/sscc/#{shipper.id}/serials"}
                      title={"Packed in SSCC #{shipper.code}"}
                      class="inline-flex min-w-0 items-center gap-1 rounded-full bg-thamani-forest px-2 py-0.5 font-mono text-[11px] font-semibold text-thamani-on-accent transition hover:bg-thamani-forest/85"
                    >
                      <.icon name="hero-archive-box" class="size-3 shrink-0" />
                      <span class="truncate">SSCC {shipper.code}</span>
                    </.link>
                <% end %>
              </div>
              <div class="mt-3 flex items-center gap-3">
                <canvas
                  id={"serial-datamatrix-#{dom_key(serial.serial)}"}
                  phx-hook="DataMatrix"
                  phx-update="ignore"
                  data-gs1-text={gs1_text(@product, @selected_batch, serial)}
                  class="size-28 shrink-0 bg-td-surface p-1"
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
                  class="inline-flex items-center gap-1.5 rounded-lg bg-thamani-forest px-3 py-2 text-xs font-semibold text-thamani-on-accent transition hover:bg-thamani-forest/90"
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
                  class="inline-flex items-center gap-1.5 rounded-lg border border-thamani-stone bg-td-surface px-3 py-2 text-xs font-semibold text-thamani-forest transition hover:bg-td-wash"
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
