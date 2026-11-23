defmodule ThamaniDawaWeb.ManufacturerProductLive.Serials do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Distributor.GlnLookup
  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Sites
  alias ThamaniDawaWeb.DistributorPagination

  @page_size 50
  @preview_size 8

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
     |> assign(:batch_fully_packed, false)
     |> assign(:batch_serial_total, 0)
     |> assign(:batch_packed, 0)
     |> assign(:label_serial, nil)
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
      |> assign(:view, if(params["view"] == "serials", do: "serials", else: "batch"))
      |> assign(:state_filter, if(params["state"] in ["packed", "unpacked"], do: params["state"], else: ""))
      |> assign(:return_to, ThamaniDawaWeb.ReturnTo.safe(params["return_to"] || "", ""))
      |> assign(:back_path, ThamaniDawaWeb.ReturnTo.path(params, ~p"/manufacturer/products"))
      |> assign_new(:print_open, fn -> false end)
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
          serial_shippers: %{},
          batch_fully_packed: false
        )

      batch ->
        {socket, result} = batch_serials(socket, batch.batch_no)

        {shippers, by_serial} =
          Manufacturing.list_batch_shippers(
            org_id(socket),
            socket.assigns.product.gtin,
            batch.batch_no
          )

        socket =
          assign(socket,
            batch_shippers: shippers,
            serial_shippers: by_serial,
            batch_fully_packed: fully_packed?(result, by_serial)
          )

        case result do
          {:ok, serials} ->
            all_serials = serials

            serials =
              serials
              |> filter_serials(search, batch)
              |> filter_state(socket.assigns.state_filter, by_serial)

            page_size = if socket.assigns.view == "serials", do: @page_size, else: @preview_size

            page =
              DistributorPagination.page(
                serials,
                DistributorPagination.page_number(params),
                page_size
              )

            assign(socket,
              selected_batch: batch,
              serial_page: page,
              serials_error: nil,
              batch_serial_total: length(all_serials),
              batch_packed: Enum.count(all_serials, &Map.has_key?(by_serial, &1.serial)),
              label_serial: List.first(all_serials)
            )

          {:error, reason} ->
            assign(socket, selected_batch: batch, serial_page: nil, serials_error: reason)
        end
    end
  end

  # Every issued serial in the batch already sits in a shipper SSCC.
  defp fully_packed?({:ok, [_ | _] = serials}, by_serial),
    do: Enum.all?(serials, &Map.has_key?(by_serial, &1.serial))

  defp fully_packed?(_result, _by_serial), do: false

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

  defp filter_state(serials, "packed", by_serial), do: Enum.filter(serials, &Map.has_key?(by_serial, &1.serial))
  defp filter_state(serials, "unpacked", by_serial), do: Enum.reject(serials, &Map.has_key?(by_serial, &1.serial))
  defp filter_state(serials, _state, _by_serial), do: serials

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

  def handle_event("set_filter", %{"field" => "state", "value" => value}, socket) do
    query = page_query(socket.assigns, state: value)
    {:noreply, push_patch(socket, to: ~p"/manufacturer/products/#{socket.assigns.product.gtin}/serials?#{query}")}
  end

  def handle_event("open_print", _params, socket), do: {:noreply, assign(socket, :print_open, true)}
  def handle_event("close_print", _params, socket), do: {:noreply, assign(socket, :print_open, false)}

  def handle_event("reset", _params, socket) do
    to =
      if socket.assigns.view == "serials",
        do: view_serials_path(socket.assigns, search: "", state: ""),
        else: ~p"/manufacturer/products/#{socket.assigns.product.gtin}/serials"

    {:noreply, push_patch(socket, to: to)}
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
         |> assign(:pack_to_party, party)
         |> assign(:to_gln_query, "#{party.gln} · #{party.company}")
         |> assign(:to_gln_results, [])
         |> assign(:to_gln_search_status, :selected)}
    end
  end

  def handle_event("submit_pack", %{"pack" => params}, socket) do
    %{product: product, selected_batch: batch, pack_serials: all, pack_selected: selected} =
      socket.assigns

    serials = Enum.filter(all, &MapSet.member?(selected, &1))
    attrs = put_pack_parties(params, socket.assigns)

    case Manufacturing.pack_serials_into_shipper(
           org_id(socket),
           product,
           batch,
           serials,
           attrs,
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

  # Company/address for the label: the From facility from the org's sites,
  # the To party from the GS1 directory result the user picked.
  defp put_pack_parties(params, assigns) do
    from = Enum.find(assigns.pack_facilities, &(&1.gln == params["from_gln"]))

    to =
      with %{gln: gln} = party <- assigns.pack_to_party,
           ^gln <- params["to_gln"],
           do: party,
           else: (_ -> nil)

    Map.merge(params, %{
      "from_company_name" => from && from.name,
      "from_address" => from && from.address,
      "to_company_name" => to && to.company,
      "to_address" => to && to.address
    })
  end

  defp reset_pack(socket) do
    socket
    |> assign(:to_gln_query, "")
    |> assign(:pack_to_party, nil)
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

  defp search_params(socket, search), do: page_query(socket.assigns, search: search)

  # Query for this page, keeping batch, view, state and return_to.
  defp page_query(assigns, overrides) do
    base = [
      batch: assigns.selected_batch && assigns.selected_batch.batch_no,
      view: if(assigns.view == "serials", do: "serials"),
      state: assigns.state_filter,
      search: assigns.search,
      return_to: assigns.return_to
    ]

    base
    |> Keyword.merge(overrides)
    |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
  end

  defp batch_path(assigns, batch_no) do
    query =
      Enum.reject([batch: batch_no, return_to: assigns.return_to], fn {_k, v} -> v in [nil, ""] end)

    ~p"/manufacturer/products/#{assigns.product.gtin}/serials?#{query}"
  end

  defp view_serials_path(assigns, overrides \\ []) do
    query = page_query(%{assigns | view: "serials"}, overrides)
    ~p"/manufacturer/products/#{assigns.product.gtin}/serials?#{query}"
  end

  defp sscc_serials_path(assigns, shipper) do
    ~p"/manufacturer/sscc/#{shipper.id}/serials?#{%{return_to: current_page(assigns)}}"
  end

  defp current_page(assigns),
    do: ~p"/manufacturer/products/#{assigns.product.gtin}/serials?#{page_query(assigns, search: "")}"

  defp sgtin(product, serial), do: "(01)#{gtin14(product)}(21)#{serial.serial}"

  defp label_date(nil), do: ""
  defp label_date(date), do: Calendar.strftime(date, "%d.%m.%Y")

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
      <%= if @view == "serials" and @selected_batch do %>
        {view_serials(assigns)}
      <% else %>
      <.td_back_link
        id="serials-back"
        to={@back_path}
        label={ThamaniDawaWeb.ReturnTo.label(@back_path, "Back to Products")}
      />
      <div class="td-idh">
        <div>
          <h1 class="td-idh-title">{@product.name}</h1>
          <p class="td-idh-sub">
            GTIN <span class="font-mono">{@product.gtin}</span>
            <span :if={is_list(@batches)}> · {length(@batches)} {if length(@batches) == 1, do: "batch", else: "batches"}</span>
          </p>
        </div>
        <div class="td-idh-actions">
          <.td_button
            id="batches-generate-serials"
            label="Generate serials"
            navigate={~p"/manufacturer/products/#{@product.gtin}/serials/new"}
          />
          <.td_button
            :if={@selected_batch}
            id="export-batch-serials"
            glyph="download-simple"
            label="Export CSV"
            href={~p"/manufacturer/products/#{@product.gtin}/batches/#{@selected_batch.batch_no}/serials/export"}
          />
          <.td_button
            :if={@selected_batch && !@pack_open && !@batch_fully_packed}
            id="open-pack-serials"
            label="Create shipper SSCC"
            phx-click="open_pack"
            phx-disable-with="Loading unpacked serials…"
          />
          <span :if={@batch_fully_packed} id="batch-fully-packed">
            <.td_badge tone="success" label="All serials packed" />
          </span>
        </div>
      </div>

      <div id="manufacturer-serial-batches" class="td-pad td-batch-split">
        <aside class="td-card td-batch-rail">
          <.td_card_header
            title="Batches"
            subtitle={if is_list(@batches), do: "#{length(@batches)} #{if length(@batches) == 1, do: "batch", else: "batches"} for this product", else: "Loading from GS1"}
          />
          <p :if={is_nil(@batches)} id="serial-batches-loading" class="td-note td-pad">Loading batches from GS1…</p>
          <div :if={@batches_error} id="serial-batches-error" class="td-ban is-danger m-3">
            <span>{error_message(@batches_error)}</span>
            <.td_button id="retry-serial-batches" label="Retry" phx-click="retry" />
          </div>
          <div :if={@batches == [] and is_nil(@batches_error)} id="serial-batches-empty" class="td-pad">
            <p class="td-empty-title">No serials yet</p>
            <p class="td-note">Generate serials to create the first batch for this product.</p>
          </div>
          <.link
            :for={batch <- @batches || []}
            id={"serial-batch-#{dom_key(batch.batch_no)}"}
            patch={batch_path(assigns, batch.batch_no)}
            class={["td-batch-item", @selected_batch && @selected_batch.batch_no == batch.batch_no && "is-on"]}
          >
            <span class="td-batch-l1">
              <span class="font-mono">{batch.batch_no}</span>
              <.td_badge :if={new_batch?(batch)} tone="info" label="New" />
            </span>
            <span class="td-batch-l2">
              <span>{batch.serial_count} serials</span>
              <span id={"serial-batch-created-at-#{dom_key(batch.batch_no)}"}>
                {ThamaniDawaWeb.TimeFormat.datetime(batch.created_at)}
              </span>
            </span>
          </.link>
          <p :if={is_list(@batches) and @batches != []} class="td-note td-pad">
            A batch appears here each time you generate serials for this product.
          </p>
        </aside>

        <div :if={@selected_batch} id="selected-serial-batch" class="td-batch-col">
          <div class="td-card">
            <div id="primary-serial-batch-details" class="td-kv-grid is-pad is-6">
              <div id="primary-serial-batch-number" class="td-kv">
                <span class="td-kv-label">Batch</span>
                <span class="td-kv-value is-mono">{@selected_batch.batch_no}</span>
              </div>
              <div id="primary-serial-gtin" class="td-kv">
                <span class="td-kv-label">GTIN</span>
                <span class="td-kv-value is-mono">{@product.gtin}</span>
              </div>
              <div id="primary-serial-production-date" class="td-kv">
                <span class="td-kv-label">Produced</span>
                <span class="td-kv-value">{long_date(@selected_batch.production_date)}</span>
              </div>
              <div id="primary-serial-expiry-date" class="td-kv">
                <span class="td-kv-label">Expires</span>
                <span class="td-kv-value">{long_date(@selected_batch.expiry_date)}</span>
              </div>
              <div class="td-kv">
                <span class="td-kv-label">Serials</span>
                <span class="td-kv-value">{@batch_serial_total}</span>
              </div>
              <div id="primary-serial-packed" class="td-kv">
                <span class="td-kv-label">Packed</span>
                <span class="td-kv-value">{@batch_packed} of {@batch_serial_total}</span>
              </div>
            </div>
          </div>

          <div :if={@pack_open} class="td-card">
          <section
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

          </div>

          <div :if={@serials_error} id="manufacturer-serials-error" class="td-ban is-danger">
            <span>{error_message(@serials_error)}</span>
            <.td_button id="retry-manufacturer-serials" label="Retry" phx-click="retry" />
          </div>

          <div :if={@serial_page} class="td-batch-pair">
            <div class="td-card" id="serial-preview-card">
              <.td_card_header
                title={"Serials in #{@selected_batch.batch_no}"}
                subtitle={"The first #{length(@serial_page.entries)} of #{@batch_serial_total}. Print or export the whole batch from here."}
              >
                <:actions>
                  <.td_button
                    id="view-all-serials"
                    label="View all serials"
                    patch={view_serials_path(assigns)}
                  />
                </:actions>
              </.td_card_header>
              <table class="td-rows is-static" id="manufacturer-serials">
                <thead>
                  <tr><th>Serial (SGTIN)</th><th>State</th><th>Shipper SSCC</th></tr>
                </thead>
                <tbody>
                  <.serial_row :for={serial <- @serial_page.entries} serial={serial} product={@product} batch={@selected_batch} serial_shippers={@serial_shippers} return_to={current_page(assigns)} full={false} />
                </tbody>
              </table>
              <p class="td-note td-pad">
                Showing <b>{length(@serial_page.entries)}</b> of <b>{@batch_serial_total}</b> serials
              </p>
            </div>

            <div :if={@label_serial} class="td-card" id="serial-label-preview">
              <.td_card_header title="Label preview" subtitle="One label per serial, 50 × 25 mm">
                <:actions>
                  <.td_button id="open-print-labels" variant="primary" glyph="printer" label="Print labels" phx-click="open_print" />
                </:actions>
              </.td_card_header>
              <div class="td-pad">
                <.serial_label id="serial-label-sample" product={@product} batch={@selected_batch} serial={@label_serial} />
                <p class="td-note mt-3">All {@batch_serial_total} labels use this layout.</p>
              </div>
            </div>
          </div>

          <div :if={@batch_shippers != []} id="batch-shipper-ssccs" class="td-card">
            <.td_card_header
              title={"Shipper SSCCs for #{@selected_batch.batch_no}"}
              subtitle={"#{length(@batch_shippers)} #{if length(@batch_shippers) == 1, do: "shipper", else: "shippers"} packed from this batch"}
            />
            <table class="td-rows is-static">
              <thead>
                <tr><th>SSCC</th><th>To GLN</th><th class="is-num">Serials</th><th>Packed</th><th><span class="sr-only">Actions</span></th></tr>
              </thead>
              <tbody>
                <tr :for={shipper <- @batch_shippers} id={"batch-shipper-#{shipper.id}"}>
                  <td class="font-mono">{shipper.code}</td>
                  <td class="font-mono">{shipper.to_gln || "Not set"}</td>
                  <td class="is-num">{shipper.count_of_trade_items || 0}</td>
                  <td>{ThamaniDawaWeb.TimeFormat.date(shipper.inserted_at)}</td>
                  <td class="td-row-actions">
                    <.td_button id={"batch-shipper-serials-#{shipper.id}"} label="Serials" navigate={sscc_serials_path(assigns, shipper)} />
                    <.td_button id={"batch-shipper-label-#{shipper.id}"} glyph="printer" label="Print label" navigate={~p"/manufacturer/sscc/#{shipper.id}/label"} />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
      <% end %>

      <.print_labels_modal
        :if={@print_open and @selected_batch}
        product={@product}
        batch={@selected_batch}
        serials={Map.get(@serials_cache, @selected_batch.batch_no, [])}
      />
    </Layouts.manufacturer_shell>
    """
  end
  defp new_batch?(batch) do
    case created_at(batch.created_at) do
      %DateTime{} = at -> DateTime.diff(DateTime.utc_now(), at, :hour) < 24
      _ -> false
    end
  end

  defp created_at(%DateTime{} = at), do: at
  defp created_at(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")

  defp created_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> at
      _ -> nil
    end
  end

  defp created_at(_value), do: nil

  attr :serial, :map, required: true
  attr :product, :map, required: true
  attr :batch, :map, required: true
  attr :serial_shippers, :map, required: true
  attr :return_to, :string, required: true
  attr :full, :boolean, default: false

  defp serial_row(assigns) do
    assigns = assign(assigns, :shipper, Map.get(assigns.serial_shippers, assigns.serial.serial))

    ~H"""
    <tr id={"manufacturer-serial-#{dom_key(@serial.serial)}"}>
      <td class="font-mono">{sgtin(@product, @serial)}</td>
      <td :if={@full} class="font-mono">{@batch.batch_no}</td>
      <td :if={@full}>{long_date(@batch.expiry_date)}</td>
      <td>
        <span :if={is_nil(@shipper)} id={"serial-unpacked-#{dom_key(@serial.serial)}"}>
          <.td_badge tone="neutral" label="Unpacked" />
        </span>
        <.td_badge :if={@shipper} tone="success" label="Packed" />
      </td>
      <td>
        <span :if={is_nil(@shipper)} class="td-s12">Not packed</span>
        <.link
          :if={@shipper}
          id={"serial-sscc-#{dom_key(@serial.serial)}"}
          class="td-link font-mono"
          navigate={~p"/manufacturer/sscc/#{@shipper.id}/serials?#{%{return_to: @return_to}}"}
          title={"Packed in SSCC #{@shipper.code}"}
        >
          {@shipper.code}
        </.link>
      </td>
    </tr>
    """
  end

  attr :id, :string, required: true
  attr :product, :map, required: true
  attr :batch, :map, required: true
  attr :serial, :map, required: true
  attr :class, :string, default: nil

  defp serial_label(assigns) do
    ~H"""
    <div id={@id} class={["td-serial-label", @class]}>
      <canvas
        id={"#{@id}-datamatrix"}
        phx-hook="DataMatrix"
        phx-update="ignore"
        data-gs1-text={gs1_text(@product, @batch, @serial)}
        class="td-serial-label-dm"
      ></canvas>
      <div class="td-serial-label-tx">
        <b>{@product.name}</b>
        <span>GTIN {@product.gtin}</span>
        <span>BATCH {@batch.batch_no}</span>
        <span>EXP {label_date(@batch.expiry_date)}</span>
        <span>SN {@serial.serial}</span>
      </div>
    </div>
    """
  end

  attr :product, :map, required: true
  attr :batch, :map, required: true
  attr :serials, :list, required: true

  defp print_labels_modal(assigns) do
    ~H"""
    <.modal
      id="print-labels-modal"
      show
      size="form"
      title="Print labels"
      subtitle={"#{length(@serials)} DataMatrix labels for batch #{@batch.batch_no}, one per serial."}
      on_cancel={JS.push("close_print")}
    >
      <div class="td-kv-list">
        <div class="td-kv"><span class="td-kv-label">Product</span><span class="td-kv-value">{@product.name}</span></div>
        <div class="td-kv"><span class="td-kv-label">Batch</span><span class="td-kv-value is-mono">{@batch.batch_no}</span></div>
        <div class="td-kv"><span class="td-kv-label">Label size</span><span class="td-kv-value">50 × 25 mm</span></div>
        <div class="td-kv"><span class="td-kv-label">Labels</span><span class="td-kv-value">{length(@serials)}</span></div>
      </div>
      <div id="print-labels-sheet" class="td-print-sheet" aria-hidden="true">
        <.serial_label
          :for={serial <- @serials}
          id={"print-label-#{dom_key(serial.serial)}"}
          class="printable-serial-label"
          product={@product}
          batch={@batch}
          serial={serial}
        />
      </div>
      <:footer>
        <.td_button id="cancel-print-labels" label="Cancel" phx-click="close_print" />
        <.td_button
          id="print-batch-labels"
          variant="primary"
          glyph="printer"
          label={"Print #{length(@serials)} labels"}
          phx-hook="PrintAllLabels"
          data-print-target=".printable-serial-label"
          data-label-size="50mm 25mm"
          disabled={@serials == []}
        />
      </:footer>
    </.modal>
    """
  end

  defp view_serials(assigns) do
    ~H"""
    <.td_back_link
      id="view-serials-back"
      to={batch_path(assigns, @selected_batch.batch_no)}
      label={"Back to batch #{@selected_batch.batch_no}"}
    />
    <div class="td-idh">
      <div>
        <h1 class="td-idh-title">Serials in {@selected_batch.batch_no}</h1>
        <p class="td-idh-sub">{@product.name} · GTIN <span class="font-mono">{@product.gtin}</span></p>
      </div>
      <div class="td-idh-actions">
        <.td_button
          id="export-batch-serials"
          glyph="download-simple"
          label="Export CSV"
          href={~p"/manufacturer/products/#{@product.gtin}/batches/#{@selected_batch.batch_no}/serials/export"}
        />
        <.td_button id="open-print-labels" glyph="printer" label="Print labels" phx-click="open_print" />
      </div>
    </div>

    <div class="td-toolbar">
      <form id="manufacturer-serial-search" phx-change="search">
        <.td_search name="search" value={@search} placeholder="Search serials" phx-debounce="300" />
      </form>
      <.td_filter_menu
        id="serials"
        field="state"
        label="State"
        value={@state_filter}
        options={[{"", "All"}, {"unpacked", "Unpacked"}, {"packed", "Packed"}]}
      />
      <span class="td-toolbar-count" id="view-serials-count">
        <b>{@batch_serial_total}</b> serials · <b>{@batch_packed}</b> packed
      </span>
    </div>

    <div :if={@serials_error} id="manufacturer-serials-error" class="td-ban is-danger m-4">
      <span>{error_message(@serials_error)}</span>
      <.td_button id="retry-manufacturer-serials" label="Retry" phx-click="retry" />
    </div>

    <div :if={@serial_page && @serial_page.total_entries == 0} id="view-serials-empty" class="td-pad td-empty-wrap">
      <div class="td-card td-empty-card">
        <p class="td-empty-title">No matching serials</p>
        <p class="td-note">Try another serial, or clear the search and filters.</p>
        <.td_button id="view-serials-clear" label="Clear search" phx-click="reset" />
      </div>
    </div>

    <div :if={@serial_page && @serial_page.total_entries > 0} class="td-list-table">
      <table class="td-rows" id="manufacturer-serials">
        <thead>
          <tr><th>Serial (SGTIN)</th><th>Batch</th><th>Expires</th><th>State</th><th>Shipper SSCC</th></tr>
        </thead>
        <tbody>
          <.serial_row
            :for={serial <- @serial_page.entries}
            serial={serial}
            product={@product}
            batch={@selected_batch}
            serial_shippers={@serial_shippers}
            return_to={current_page(assigns)}
            full
          />
        </tbody>
      </table>
    </div>
    <.pagination
      :if={@serial_page && @serial_page.total_entries > 0}
      page={@serial_page}
      path={view_serials_path(assigns)}
    />
    """
  end
end
