defmodule ThamaniDawaWeb.ManufacturerProductLive.Serials do
  use ThamaniDawaWeb, :live_view

  require Logger

  alias ThamaniDawa.Manufacturing
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
     |> assign(:serials_loading, false)
     |> assign(:batch_shippers, [])
     |> assign(:serial_shippers, %{})
     |> assign(:batch_fully_packed, false)
     |> assign(:batch_serial_total, 0)
     |> assign(:batch_packed, 0)
     |> assign(:label_serial, nil)}
  end

  # Nested GS1 flow, kept light on the API: the batch list is fetched once
  # per visit (`getbarcode_batches`), and only the page of serials on screen
  # is fetched (`get_batch_serials` with paging). Both run as async tasks so
  # the page joins straight away; waiting on GS1 inside the join made large
  # products time out and reconnect in a loop. Printing fetches the whole
  # batch when its dialog opens. Nothing is fetched on the static render.
  def handle_params(params, _url, socket) do
    search = Map.get(params, "search", "")

    socket =
      socket
      |> assign(:search, search)
      |> assign(:params, params)
      |> assign(:view, if(params["view"] == "serials", do: "serials", else: "batch"))
      |> assign(
        :state_filter,
        if(params["state"] in ["packed", "unpacked"], do: params["state"], else: "")
      )
      |> assign(:return_to, ThamaniDawaWeb.ReturnTo.safe(params["return_to"] || "", ""))
      |> assign(:back_path, ThamaniDawaWeb.ReturnTo.path(params, ~p"/manufacturer/products"))
      |> assign_new(:print_open, fn -> false end)
      |> assign_new(:serials_loading, fn -> false end)
      |> ensure_batches()

    {:noreply, select_batch(socket)}
  end

  def handle_async(:batches, {:ok, result}, socket) do
    socket =
      case result do
        {:ok, batches} -> assign(socket, batches: batches, batches_error: nil)
        {:error, reason} -> assign(socket, batches: [], batches_error: reason)
      end

    {:noreply, select_batch(socket)}
  end

  def handle_async(:batches, {:exit, reason}, socket) do
    Logger.error("Serials page: loading batches crashed: #{inspect(reason)}")
    {:noreply, assign(socket, batches: [], batches_error: :unavailable)}
  end

  def handle_async(:serials, {:ok, {shippers, by_serial, result}}, socket) do
    batch = socket.assigns.selected_batch
    total = (batch && batch.serial_count) || 0
    packed = map_size(by_serial)

    socket =
      assign(socket,
        serials_loading: false,
        batch_shippers: shippers,
        serial_shippers: by_serial,
        batch_packed: packed,
        batch_fully_packed: total > 0 and packed >= total
      )

    socket =
      case result do
        {:ok, page} ->
          assign(socket,
            serial_page: page,
            serials_error: nil,
            label_serial: List.first(page.entries)
          )

        {:error, reason} ->
          Logger.warning(
            "Serials page: GS1 get_batch_serials failed for #{socket.assigns.product.gtin} batch #{inspect(batch && batch.batch_no)}: #{inspect(reason)}"
          )

          assign(socket, serial_page: nil, serials_error: reason, label_serial: nil)
      end

    {:noreply, socket}
  end

  def handle_async(:serials, {:exit, reason}, socket) do
    Logger.error("Serials page: loading serials crashed: #{inspect(reason)}")

    {:noreply,
     assign(socket,
       serials_loading: false,
       serial_page: nil,
       serials_error: :unavailable,
       label_serial: nil
     )}
  end

  defp ensure_batches(%{assigns: %{batches: nil}} = socket) do
    if connected?(socket) do
      organization_id = org_id(socket)
      gtin = socket.assigns.product.gtin

      socket
      |> cancel_async(:batches)
      |> start_async(:batches, fn ->
        Manufacturing.fetch_product_batches(organization_id, gtin)
      end)
    else
      socket
    end
  end

  defp ensure_batches(socket), do: socket

  defp select_batch(%{assigns: %{batches: nil}} = socket), do: socket

  defp select_batch(socket) do
    params = socket.assigns.params
    search = socket.assigns.search
    visible = filter_batches(socket.assigns.batches, search)
    selected = Enum.find(visible, &(&1.batch_no == params["batch"])) || List.first(visible)

    case selected do
      nil ->
        socket
        |> cancel_async(:serials)
        |> assign(
          selected_batch: nil,
          serial_page: nil,
          serials_error: nil,
          serials_loading: false,
          batch_shippers: [],
          serial_shippers: %{},
          batch_fully_packed: false
        )

      batch ->
        organization_id = org_id(socket)
        gtin = socket.assigns.product.gtin
        state = socket.assigns.state_filter
        page_size = if socket.assigns.view == "serials", do: @page_size, else: @preview_size
        page_number = DistributorPagination.page_number(params)
        serial_search = serial_search(search, batch)

        socket
        |> assign(
          selected_batch: batch,
          batch_serial_total: batch.serial_count || 0,
          serials_loading: true,
          serials_error: nil
        )
        |> cancel_async(:serials)
        |> start_async(:serials, fn ->
          {shippers, by_serial} =
            Manufacturing.list_batch_shippers(organization_id, gtin, batch.batch_no)

          result =
            serial_page(
              {organization_id, gtin, state},
              batch,
              by_serial,
              serial_search,
              page_number,
              page_size
            )

          {shippers, by_serial, result}
        end)
    end
  end

  # Only the page on screen is fetched from GS1. Packed serials are known
  # locally from this batch's shippers, so that filter needs no GS1 call;
  # unpacked asks GS1 to leave them out.
  defp serial_page({_org, _gtin, "packed"}, _batch, by_serial, search, page_number, page_size) do
    entries =
      by_serial
      |> Map.keys()
      |> Enum.filter(&(search == "" or String.contains?(String.downcase(&1), search)))
      |> Enum.sort()
      |> Enum.map(&%{serial: &1, payload: nil, human_readable: nil})

    {:ok, DistributorPagination.page(entries, page_number, page_size)}
  end

  defp serial_page(
         {organization_id, gtin, state},
         batch,
         by_serial,
         search,
         page_number,
         page_size
       ) do
    exclude = if state == "unpacked", do: Map.keys(by_serial), else: []

    Manufacturing.fetch_batch_serial_page(
      organization_id,
      gtin,
      batch.batch_no,
      page: page_number,
      per_page: page_size,
      search: search,
      exclude: exclude
    )
  end

  # A search matching the batch number shows the whole batch; otherwise it
  # narrows the batch's serials.
  defp serial_search(search, batch) do
    term = search |> String.trim() |> String.downcase()

    if term == "" or String.contains?(String.downcase(batch.batch_no), term),
      do: "",
      else: term
  end

  # Printing needs every serial in the batch, so it is fetched only when the
  # print dialog opens, then kept for this visit. That full list is also the
  # write-through into local issued_count — a paged GS1 fetch is not.
  defp ensure_all_serials(socket, batch_no) do
    case socket.assigns.serials_cache do
      %{^batch_no => _serials} ->
        socket

      cache ->
        case Manufacturing.fetch_batch_serials(
               org_id(socket),
               socket.assigns.product.gtin,
               batch_no
             ) do
          {:ok, serials} ->
            persist_fetched_serials(socket, serials)
            assign(socket, :serials_cache, Map.put(cache, batch_no, serials))

          {:error, reason} ->
            assign(socket, :serials_error, reason)
        end
    end
  end

  defp persist_fetched_serials(socket, serials) do
    case socket.assigns.selected_batch do
      %{local_id: id} when is_integer(id) ->
        local = Manufacturing.get_batch!(org_id(socket), id)

        Manufacturing.persist_issued_serials(
          org_id(socket),
          socket.assigns.product,
          local,
          serials
        )

        :ok

      _ ->
        :ok
    end
  end

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

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/manufacturer/products/#{socket.assigns.product.gtin}/serials?#{search_params(socket, search)}"
     )}
  end

  def handle_event("set_filter", %{"field" => "state", "value" => value}, socket) do
    query = page_query(socket.assigns, state: value)

    {:noreply,
     push_patch(socket,
       to: ~p"/manufacturer/products/#{socket.assigns.product.gtin}/serials?#{query}"
     )}
  end

  def handle_event("open_print", _params, socket) do
    socket = ensure_all_serials(socket, socket.assigns.selected_batch.batch_no)
    {:noreply, assign(socket, :print_open, true)}
  end

  def handle_event("close_print", _params, socket),
    do: {:noreply, assign(socket, :print_open, false)}

  def handle_event("reset", _params, socket) do
    to =
      if socket.assigns.view == "serials",
        do: view_serials_path(socket.assigns, search: "", state: ""),
        else: ~p"/manufacturer/products/#{socket.assigns.product.gtin}/serials"

    {:noreply, push_patch(socket, to: to)}
  end

  def handle_event("retry", _params, socket) do
    {:noreply,
     socket
     |> assign(batches: nil, serials_cache: %{})
     |> push_patch(to: ~p"/manufacturer/products/#{socket.assigns.product.gtin}/serials")}
  end

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
      Enum.reject([batch: batch_no, return_to: assigns.return_to], fn {_k, v} ->
        v in [nil, ""]
      end)

    ~p"/manufacturer/products/#{assigns.product.gtin}/serials?#{query}"
  end

  defp pack_path(assigns) do
    query =
      Enum.reject(
        [batch: assigns.selected_batch.batch_no, return_to: current_page(assigns)],
        fn {_k, v} -> v in [nil, ""] end
      )

    ~p"/manufacturer/products/#{assigns.product.gtin}/serials/pack?#{query}"
  end

  defp view_serials_path(assigns, overrides \\ []) do
    query = page_query(%{assigns | view: "serials"}, overrides)
    ~p"/manufacturer/products/#{assigns.product.gtin}/serials?#{query}"
  end

  defp sscc_serials_path(assigns, shipper) do
    ~p"/manufacturer/sscc/#{shipper.id}/serials?#{%{return_to: current_page(assigns)}}"
  end

  defp current_page(assigns),
    do:
      ~p"/manufacturer/products/#{assigns.product.gtin}/serials?#{page_query(assigns, search: "")}"

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
  defp long_date(date), do: ThamaniDawaWeb.TimeFormat.date(date)

  defp error_message(:unconfigured),
    do: "Add your GS1 API key in organization settings to load serials."

  defp error_message(reason) when reason in [:unauthorized, :forbidden],
    do: "GS1 rejected your API key."

  defp error_message({:invalid, message}), do: message

  defp error_message({:unavailable, "HTTP " <> detail}) do
    status = detail |> String.split(":", parts: 2) |> hd()
    "GS1 couldn't load serials (error #{status}). Try again shortly."
  end

  defp error_message(_reason), do: "Couldn't reach GS1 to load serials. Try again shortly."

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/products"}
    >
      <:search :if={@view == "serials" and @selected_batch}>
        <form id="manufacturer-serial-search" phx-change="search">
          <.td_search
            name="search"
            value={@search}
            placeholder="Search serials"
            shortcut="⌘K"
            phx-debounce="300"
          />
        </form>
      </:search>
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
              <span :if={is_list(@batches)}> · {length(@batches)} {if length(@batches) == 1,
                do: "batch",
                else: "batches"}</span>
            </p>
          </div>
          <div class="td-idh-actions">
            <.td_button
              id="batches-generate-serials"
              label="Generate serials"
              navigate={~p"/manufacturer/products/#{@product.gtin}/serials/new"}
              tip="Issue another GS1 batch and DataMatrix serials for this product."
            />
            <.td_button
              :if={@selected_batch}
              id="export-batch-serials"
              glyph="download-simple"
              label="Export CSV"
              tip="Download this batch's serials as a spreadsheet."
              href={
                ~p"/manufacturer/products/#{@product.gtin}/batches/#{@selected_batch.batch_no}/serials/export"
              }
            />
            <.td_button
              :if={@selected_batch && !@batch_fully_packed}
              id="open-pack-serials"
              variant="primary"
              label="Create shipper SSCC"
              navigate={pack_path(assigns)}
              tip="Pack unpacked serials into a shipper SSCC for dispatch."
              tip_align="end"
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
              subtitle={
                if is_list(@batches),
                  do:
                    "#{length(@batches)} #{if length(@batches) == 1, do: "batch", else: "batches"} for this product",
                  else: "Loading from GS1"
              }
            />
            <p :if={is_nil(@batches)} id="serial-batches-loading" class="td-note td-pad">
              Loading batches from GS1…
            </p>
            <div :if={@batches_error} id="serial-batches-error" class="td-ban is-danger m-3">
              <span>{error_message(@batches_error)}</span>
              <.td_button id="retry-serial-batches" label="Retry" phx-click="retry" />
            </div>
            <div :if={@batches == [] and is_nil(@batches_error)} id="serial-batches-empty">
              <.td_empty
                icon="stack"
                title="No serials yet"
                hint="Generate serials to create the first batch for this product."
              >
                <:action>
                  <.td_button
                    variant="secondary"
                    label="Generate serials"
                    patch={~p"/manufacturer/products/#{@product.gtin}/serials/new"}
                  />
                </:action>
              </.td_empty>
            </div>
            <.link
              :for={batch <- @batches || []}
              id={"serial-batch-#{dom_key(batch.batch_no)}"}
              patch={batch_path(assigns, batch.batch_no)}
              class={[
                "td-batch-item",
                @selected_batch && @selected_batch.batch_no == batch.batch_no && "is-on"
              ]}
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

            <p :if={@serials_loading} id="manufacturer-serials-loading" class="td-note td-pad">
              Loading serials from GS1...
            </p>
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
                <table class="td-rows is-static is-clip" id="manufacturer-serials">
                  <thead>
                    <tr>
                      <th>Code</th><th>Serial (SGTIN)</th><th>State</th><th>Shipper SSCC</th>
                    </tr>
                  </thead>
                  <tbody>
                    <.serial_row
                      :for={serial <- @serial_page.entries}
                      serial={serial}
                      product={@product}
                      batch={@selected_batch}
                      serial_shippers={@serial_shippers}
                      return_to={current_page(assigns)}
                      full={false}
                    />
                  </tbody>
                </table>
                <p class="td-note td-serials-foot">
                  Showing <b>{length(@serial_page.entries)}</b>
                  of <b>{@batch_serial_total}</b>
                  serials
                </p>
              </div>

              <div :if={@label_serial} class="td-card" id="serial-label-preview">
                <.td_card_header title="Label preview" subtitle="One label per serial, 50 × 25 mm">
                  <:actions>
                    <.td_button
                      id="open-print-labels"
                      variant="primary"
                      glyph="printer"
                      label="Print labels"
                      phx-click="open_print"
                      tip="Print a 50 × 25 mm DataMatrix label for every serial in this batch."
                      tip_align="end"
                    />
                  </:actions>
                </.td_card_header>
                <div class="td-pad">
                  <.serial_label
                    id="serial-label-sample"
                    product={@product}
                    batch={@selected_batch}
                    serial={@label_serial}
                  />
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
                  <tr>
                    <th>SSCC</th><th>To GLN</th><th class="is-num">Serials</th><th>Packed</th><th>
                      <span class="sr-only">Actions</span>
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={shipper <- @batch_shippers} id={"batch-shipper-#{shipper.id}"}>
                    <td class="font-mono">{shipper.code}</td>
                    <td class="font-mono">{shipper.to_gln || "Not set"}</td>
                    <td class="is-num">{shipper.count_of_trade_items || 0}</td>
                    <td>{ThamaniDawaWeb.TimeFormat.date(shipper.inserted_at)}</td>
                    <td class="td-row-actions">
                      <.td_button
                        id={"batch-shipper-serials-#{shipper.id}"}
                        label="Serials"
                        navigate={sscc_serials_path(assigns, shipper)}
                      />
                      <.td_button
                        id={"batch-shipper-label-#{shipper.id}"}
                        glyph="printer"
                        label="Print label"
                        navigate={~p"/manufacturer/sscc/#{shipper.id}/label"}
                      />
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
      <td>
        <canvas
          id={"serial-dm-#{dom_key(@serial.serial)}"}
          phx-hook="DataMatrix"
          phx-update="ignore"
          data-gs1-text={gs1_text(@product, @batch, @serial)}
          class="td-serial-dm"
        ></canvas>
      </td>
      <td class="font-mono td-serial-sgtin" title={sgtin(@product, @serial)}>
        {sgtin(@product, @serial)}
      </td>
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
        <div class="td-kv">
          <span class="td-kv-label">Product</span><span class="td-kv-value">{@product.name}</span>
        </div>
        <div class="td-kv">
          <span class="td-kv-label">Batch</span><span class="td-kv-value is-mono">{@batch.batch_no}</span>
        </div>
        <div class="td-kv">
          <span class="td-kv-label">Label size</span><span class="td-kv-value">50 × 25 mm</span>
        </div>
        <div class="td-kv">
          <span class="td-kv-label">Labels</span><span class="td-kv-value">{length(@serials)}</span>
        </div>
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
        <p class="td-idh-sub">
          {@product.name} · GTIN <span class="font-mono">{@product.gtin}</span>
        </p>
      </div>
      <div class="td-idh-actions">
        <.td_button
          id="export-batch-serials"
          glyph="download-simple"
          label="Export CSV"
          tip="Download this batch's serials as a spreadsheet."
          href={
            ~p"/manufacturer/products/#{@product.gtin}/batches/#{@selected_batch.batch_no}/serials/export"
          }
        />
        <.td_button
          :if={!@batch_fully_packed}
          id="open-pack-serials"
          variant="primary"
          label="Create shipper SSCC"
          navigate={pack_path(assigns)}
          tip="Pack unpacked serials into a shipper SSCC for dispatch."
          tip_align="end"
        />
        <.td_button
          id="open-print-labels"
          glyph="printer"
          label="Print labels"
          phx-click="open_print"
          tip="Print a 50 × 25 mm DataMatrix label for every serial in this batch."
          tip_align="end"
        />
      </div>
    </div>

    <div class="td-toolbar">
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

    <p :if={@serials_loading} id="manufacturer-serials-loading" class="td-note td-pad">
      Loading serials from GS1...
    </p>
    <div :if={@serials_error} id="manufacturer-serials-error" class="td-ban is-danger m-4">
      <span>{error_message(@serials_error)}</span>
      <.td_button id="retry-manufacturer-serials" label="Retry" phx-click="retry" />
    </div>

    <div
      :if={@serial_page && @serial_page.total_entries == 0}
      id="view-serials-empty"
      class="td-pad td-empty-wrap"
    >
      <div class="td-card td-empty-card">
        <p class="td-empty-title">No matching serials</p>
        <p class="td-note">Try another serial, or clear the search and filters.</p>
        <.td_button id="view-serials-clear" label="Clear search" phx-click="reset" />
      </div>
    </div>

    <div :if={@serial_page && @serial_page.total_entries > 0} class="td-list-table">
      <table class="td-rows" id="manufacturer-serials">
        <thead>
          <tr>
            <th>Code</th><th>Serial (SGTIN)</th><th>Batch</th><th>Expires</th><th>State</th><th>
              Shipper SSCC
            </th>
          </tr>
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
