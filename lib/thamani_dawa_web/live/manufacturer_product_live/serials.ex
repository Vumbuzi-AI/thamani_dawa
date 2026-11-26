defmodule ThamaniDawaWeb.ManufacturerProductLive.Serials do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Manufacturing.Operations
  alias ThamaniDawa.RegistryCache
  alias ThamaniDawaWeb.DistributorPagination

  @page_size 50
  @preview_size 8

  def mount(%{"gtin" => gtin}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    product = Manufacturing.get_product_by_gtin!(organization_id, gtin)

    if connected?(socket) do
      Operations.subscribe_product(product.id)
    end

    {:ok,
     socket
     |> assign(:page_title, "Product serials")
     |> assign(:label_shipper, nil)
     |> assign(:product, product)
     |> assign(:search, "")
     |> assign(:batches, nil)
     |> assign(:batches_error, nil)
     |> assign(:batches_loading, false)
     |> assign(:page_params, %{})
     |> assign(:selected_batch, nil)
     |> assign(:requested_batch, nil)
     |> assign(:generation_op, nil)
     |> assign(:serials_cache, %{})
     |> assign(:serials_error, nil)
     |> assign(:serial_page, nil)
     |> assign(:batch_shippers, [])
     |> assign(:serial_shippers, %{})
     |> assign(:batch_fully_packed, false)
     |> assign(:batch_serial_total, 0)
     |> assign(:batch_packed, 0)
     |> assign(:label_serial, nil)}
  end

  # Nested GS1 flow, kept light on the API: the batch list is fetched once
  # per visit (`getbarcode_batches`), and a batch's serials only when that
  # batch is opened (`get_batch_serials`), then cached for this visit so
  # paging and searching don't call GS1 again. Nothing is fetched on the
  # static (disconnected) render.
  def handle_params(params, _url, socket) do
    search = Map.get(params, "search", "")
    requested_batch = Map.get(params, "batch")

    socket =
      socket
      |> assign(:search, search)
      |> assign(:page_params, params)
      |> assign(:requested_batch, requested_batch)
      |> assign(:view, if(params["view"] == "serials", do: "serials", else: "batch"))
      |> assign(
        :state_filter,
        if(params["state"] in ["packed", "unpacked"], do: params["state"], else: "")
      )
      |> assign(:return_to, ThamaniDawaWeb.ReturnTo.safe(params["return_to"] || "", ""))
      |> assign(:back_path, ThamaniDawaWeb.ReturnTo.path(params, ~p"/manufacturer/products"))
      |> assign_new(:print_open, fn -> false end)
      |> load_generation_status()
      |> ensure_batches()

    {:noreply, select_batch(socket, requested_batch, search, params)}
  end

  defp load_generation_status(socket) do
    op =
      Operations.generation_status_for_product(
        org_id(socket),
        socket.assigns.product.id,
        socket.assigns.requested_batch
      )

    if connected?(socket) and op &&
         op.serial_allocation_status in ["pending", "allocating"] do
      Process.send_after(self(), :refresh_pending_generation, 2_000)
    end

    assign(socket, :generation_op, op)
  end

  defp ensure_batches(%{assigns: %{batches: nil, batches_loading: false}} = socket) do
    if connected?(socket) do
      org_id = org_id(socket)
      gtin = socket.assigns.product.gtin

      socket
      |> assign(:batches_loading, true)
      |> start_async(:batches, fn -> Manufacturing.fetch_product_batches(org_id, gtin) end)
    else
      socket
    end
  end

  defp ensure_batches(socket), do: socket

  def handle_async(:batches, {:ok, {:ok, batches}}, socket),
    do: {:noreply, finish_batches(socket, batches, nil)}

  def handle_async(:batches, {:ok, {:error, reason}}, socket),
    do: {:noreply, finish_batches(socket, local_batches(socket), reason)}

  def handle_async(:batches, {:exit, _reason}, socket),
    do: {:noreply, finish_batches(socket, local_batches(socket), :unavailable)}

  defp local_batches(socket),
    do: Manufacturing.local_product_batches(org_id(socket), socket.assigns.product.gtin)

  defp finish_batches(socket, batches, error) do
    socket
    |> assign(batches: batches, batches_error: error, batches_loading: false)
    |> select_batch(
      socket.assigns.requested_batch,
      socket.assigns.search,
      socket.assigns.page_params
    )
  end

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

  defp filter_state(serials, "packed", by_serial),
    do: Enum.filter(serials, &Map.has_key?(by_serial, &1.serial))

  defp filter_state(serials, "unpacked", by_serial),
    do: Enum.reject(serials, &Map.has_key?(by_serial, &1.serial))

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

    {:noreply,
     push_patch(socket,
       to: ~p"/manufacturer/products/#{socket.assigns.product.gtin}/serials?#{query}"
     )}
  end

  def handle_event("open_print", _params, socket),
    do: {:noreply, assign(socket, :print_open, true)}

  def handle_event("close_print", _params, socket),
    do: {:noreply, assign(socket, :print_open, false)}

  def handle_event("open_shipper_label", %{"id" => id}, socket) do
    case Integer.parse(id) do
      {shipper_id, ""} ->
        case Enum.find(socket.assigns.batch_shippers, &(&1.id == shipper_id)) do
          nil -> {:noreply, socket}
          shipper -> {:noreply, assign(socket, :label_shipper, shipper)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("close_shipper_label", _params, socket),
    do: {:noreply, assign(socket, :label_shipper, nil)}

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
     |> invalidate_gs1_cache()
     |> assign(batches: nil, serials_cache: %{})
     |> push_patch(to: ~p"/manufacturer/products/#{socket.assigns.product.gtin}/serials")}
  end

  def handle_event("reconcile_serials", _params, socket) do
    operation = socket.assigns.generation_op

    if is_nil(operation) or operation.serial_allocation_status != "reconciliation_required" do
      {:noreply,
       put_flash(socket, :error, "This batch no longer needs checking. Refresh the page.")}
    else
      case Operations.reconcile_serial_allocation(operation.id) do
        {:ok, %{result: :recovered}} ->
          {:noreply,
           socket
           |> put_flash(:info, "GS1 confirmed the serials. They're now saved for this batch.")
           |> reload_after_generation()}

        {:ok, %{result: :retry_scheduled}} ->
          {:noreply,
           socket
           |> put_flash(:info, "GS1 confirmed no serials were created. We'll try again now.")
           |> reload_after_generation()}

        {:error, {:partial_allocation, found, expected}} ->
          {:noreply,
           socket
           |> put_flash(
             :error,
             "GS1 shows #{found} of #{expected} serials for this batch. Contact support so they can review them before trying again."
           )
           |> reload_after_generation()}

        {:error, _reason} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "We couldn't finish checking with GS1 just now. Try again in a moment."
           )}
      end
    end
  end

  def handle_info({:generation_updated, _operation_id}, socket) do
    {:noreply, reload_after_generation(socket)}
  end

  def handle_info(:refresh_pending_generation, socket) do
    op =
      Operations.generation_status_for_product(
        org_id(socket),
        socket.assigns.product.id,
        socket.assigns.requested_batch
      )

    if op && op.serial_allocation_status in ["pending", "allocating"] do
      Process.send_after(self(), :refresh_pending_generation, 2_000)
      {:noreply, assign(socket, :generation_op, op)}
    else
      {:noreply, reload_after_generation(socket)}
    end
  end

  defp reload_after_generation(socket) do
    socket
    |> invalidate_gs1_cache()
    |> assign(batches: nil, serials_cache: %{})
    |> load_generation_status()
    |> ensure_batches()
    |> select_batch(socket.assigns.requested_batch, socket.assigns.search, %{})
  end

  # The member API is the source of truth but slow, so reads are cached for a
  # minute. A completed generation is the one thing that changes those reads
  # from this app's side, so drop the affected keys before reloading.
  defp invalidate_gs1_cache(socket) do
    gtin = socket.assigns.product.gtin
    organization_id = org_id(socket)

    RegistryCache.delete({:gs1_product_batches, organization_id, gtin})

    batch_numbers = [
      socket.assigns.requested_batch,
      socket.assigns.selected_batch && socket.assigns.selected_batch.batch_no
    ]

    for batch_no <- batch_numbers, is_binary(batch_no) and batch_no != "" do
      RegistryCache.delete({:gs1_batch_serials, organization_id, gtin, batch_no})
    end

    socket
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

  defp prepare_shippers_path(assigns) do
    batch = assigns.selected_batch

    if batch.local_id do
      ~p"/manufacturer/aggregations/batches/#{batch.local_id}/prepare?#{%{return_to: current_page(assigns)}}"
    else
      ~p"/manufacturer/aggregations/prepare?#{%{gtin: assigns.product.gtin, batch: batch.batch_no, return_to: current_page(assigns)}}"
    end
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

  defp error_message({:invalid, _message}),
    do: "GS1 couldn't load these records. Check the batch details and try again."

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
          <div class="td-idh-text">
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
              :if={@selected_batch && @selected_batch.local_id}
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
              id="prepare-batch-shippers"
              variant="primary"
              label="Create shippers"
              navigate={prepare_shippers_path(assigns)}
              tip="Prepare this batch for physical aggregation in the mobile app."
              tip_align="end"
            />
            <.td_button
              :if={@label_serial}
              id="open-print-labels"
              glyph="printer"
              label="Print serial labels"
              phx-click="open_print"
              tip="Print a 50 × 25 mm DataMatrix label for every serial in this batch."
              tip_align="end"
            />
            <.td_button
              :if={@batch_shippers != []}
              id="print-batch-shipper-labels"
              glyph="printer"
              label="Print shipper labels"
              phx-hook="PrintAllLabels"
              data-print-container="#batch-printable-shipper-labels"
              data-print-target=".printable-sscc-label"
              data-label-size="100mm auto"
              tip="Print one SSCC label for every shipper in this batch."
              tip_align="end"
            />
            <span :if={@batch_fully_packed} id="batch-fully-packed">
              <.td_badge tone="success" label="All serials packed" />
            </span>
          </div>
        </div>

        <div
          :if={
            @generation_op &&
              @generation_op.serial_allocation_status in ["pending", "allocating"]
          }
          id="serial-allocation-pending"
          class="td-pad"
        >
          <div class="td-bnr is-info">
            <.td_icon name="arrows-clockwise" class="size-4 animate-spin" />
            <p>
              Generating {@generation_op.serial_quantity} serials for batch <b>{@generation_op.batch.batch_no}</b>… This page will update when the check finishes.
            </p>
          </div>
        </div>

        <div
          :if={
            @generation_op &&
              @generation_op.serial_allocation_status in ["failed", "reconciliation_required"]
          }
          id="serial-allocation-error"
          class="td-pad"
        >
          <div class="td-bnr is-danger">
            <.td_icon name="warning-circle" class="size-4" />
            <div>
              <p>
                <b>Batch {@generation_op.batch.batch_no}:</b>
                {@generation_op.reconciliation_note ||
                  "We couldn't finish setting up the serials for this batch."}
              </p>
              <p
                :if={@generation_op.serial_allocation_status == "failed"}
                class="td-note"
              >
                GS1 rejected this request, so no serials were created. Review the batch details and try again.
              </p>
              <p
                :if={@generation_op.serial_allocation_status == "reconciliation_required"}
                class="td-note"
              >
                We can check with GS1 now. We'll only create new serials if GS1 confirms none were made.
              </p>
              <div
                :if={@generation_op.serial_allocation_status == "failed"}
                class="mt-3"
              >
                <.link
                  id="retry-failed-generation"
                  patch={~p"/manufacturer/products/#{@product.gtin}/serials/new"}
                  class="td-link"
                >
                  Set up serials again
                </.link>
              </div>
              <div
                :if={@generation_op.serial_allocation_status == "reconciliation_required"}
                class="mt-3"
              >
                <.td_button
                  id="reconcile-serial-allocation"
                  label="Check with GS1"
                  phx-click="reconcile_serials"
                  phx-disable-with="Checking…"
                />
              </div>
            </div>
          </div>
        </div>

        <div
          :if={
            @batches == [] and is_nil(@batches_error) and
              not (@generation_op != nil and
                     @generation_op.serial_allocation_status in ["pending", "allocating"])
          }
          id="manufacturer-serial-batches-empty"
          class="td-pad"
        >
          <div class="td-card">
            <.td_empty
              id="serial-batches-empty"
              icon="stack"
              title="No serials yet"
              hint="Batches appear here after serials are generated for this product."
            />
          </div>
        </div>

        <div
          :if={@batches != [] or not is_nil(@batches_error)}
          id="manufacturer-serial-batches"
          class="td-pad td-batch-split"
        >
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
              <.td_button id="retry-serial-batches" label="Refresh" phx-click="retry" />
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
            <div :if={@label_serial} class="td-card" id="serial-label-preview">
              <.td_card_header title="Label preview" subtitle="One label per serial, 50 × 25 mm" />
              <div class="td-pad">
                <div class="flex flex-wrap items-center gap-6">
                  <.serial_label
                    id="serial-label-sample"
                    product={@product}
                    batch={@selected_batch}
                    serial={@label_serial}
                  />
                  <p class="td-note max-w-sm">
                    All <b>{@batch_serial_total}</b>
                    labels in this batch use this layout. Print them from the header, or export the serial list as CSV.
                  </p>
                </div>
              </div>
            </div>

            <div class="td-card">
              <.td_card_header
                title="Batch details"
                subtitle="GS1 identifiers, dates, and packing progress for this batch."
              />
              <div id="primary-serial-batch-details" class="td-kv-grid is-pad is-6">
                <div id="primary-serial-batch-number" class="td-kv">
                  <span class="td-kv-label">Batch</span>
                  <span class="td-kv-value is-mono">{@selected_batch.batch_no}</span>
                </div>
                <div id="primary-serial-gtin" class="td-kv">
                  <span class="td-kv-label">GTIN</span>
                  <span class="td-kv-value is-mono">{@product.gtin}</span>
                </div>
                <div id="primary-serial-batch-created-at" class="td-kv">
                  <span class="td-kv-label">Created</span>
                  <span class="td-kv-value">
                    <%= if @selected_batch.local_id do %>
                      {ThamaniDawaWeb.TimeFormat.datetime(@selected_batch.created_at)}
                    <% else %>
                      External
                    <% end %>
                  </span>
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

            <div :if={@serials_error} id="manufacturer-serials-error" class="td-ban is-danger">
              <span>{error_message(@serials_error)}</span>
              <.td_button id="retry-manufacturer-serials" label="Refresh" phx-click="retry" />
            </div>

            <div :if={@serial_page} class="td-card" id="serial-preview-card">
              <.td_card_header
                title={"Serials in #{@selected_batch.batch_no}"}
                subtitle={"The first #{length(@serial_page.entries)} of #{@batch_serial_total}. Open the full list to search, filter, or print."}
              />
              <table class="td-rows is-static" id="manufacturer-serials">
                <thead>
                  <tr>
                    <th>Code</th><th>Serial</th><th>State</th><th>Shipper SSCC</th>
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
              <div class="td-tfoot">
                <span>
                  Showing <b>{length(@serial_page.entries)}</b>
                  of <b>{@batch_serial_total}</b>
                  serials
                </span>
                <.td_button
                  id="view-all-serials"
                  label="View all serials"
                  patch={view_serials_path(assigns)}
                />
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
                        phx-click="open_shipper_label"
                        phx-value-id={shipper.id}
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
      <div
        :if={@batch_shippers != []}
        id="batch-printable-shipper-labels"
        class="td-print-sheet"
        aria-hidden="true"
      >
        <ThamaniDawaWeb.ManufacturerSsccLive.Label.sheet
          :for={shipper <- @batch_shippers}
          sscc={shipper}
          product_name={@product.name}
          id_prefix="batch-product-shipper-label"
        />
      </div>

      <ThamaniDawaWeb.ManufacturerSsccLive.Label.modal
        :if={@label_shipper}
        sscc={@label_shipper}
        product_name={@product.name}
        on_cancel={JS.push("close_shipper_label")}
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
      <td class="font-mono">{@serial.serial}</td>
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
          data-print-mode="clone"
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
      <div class="td-idh-text">
        <h1 class="td-idh-title">Serials in {@selected_batch.batch_no}</h1>
        <p class="td-idh-sub">
          {@product.name} · GTIN <span class="font-mono">{@product.gtin}</span>
        </p>
      </div>
      <div class="td-idh-actions">
        <.td_button
          :if={@selected_batch.local_id}
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
          id="prepare-batch-shippers"
          variant="primary"
          label="Create shippers"
          navigate={prepare_shippers_path(assigns)}
          tip="Prepare this batch for physical aggregation in the mobile app."
          tip_align="end"
        />
        <.td_button
          id="open-print-labels"
          glyph="printer"
          label="Print serial labels"
          phx-click="open_print"
          tip="Print a 50 × 25 mm DataMatrix label for every serial in this batch."
          tip_align="end"
        />
        <.td_button
          :if={@batch_shippers != []}
          id="print-batch-shipper-labels"
          glyph="printer"
          label="Print shipper labels"
          phx-hook="PrintAllLabels"
          data-print-container="#batch-printable-shipper-labels"
          data-print-target=".printable-sscc-label"
          data-label-size="100mm auto"
          tip="Print one SSCC label for every shipper in this batch."
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

    <div :if={@serials_error} id="manufacturer-serials-error" class="td-ban is-danger m-4">
      <span>{error_message(@serials_error)}</span>
      <.td_button id="retry-manufacturer-serials" label="Refresh" phx-click="retry" />
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
            <th>Code</th><th>Serial</th><th>Batch</th><th>Expires</th><th>State</th><th>
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
