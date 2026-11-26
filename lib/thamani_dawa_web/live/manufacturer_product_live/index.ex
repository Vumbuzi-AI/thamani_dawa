defmodule ThamaniDawaWeb.ManufacturerProductLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Sites
  alias ThamaniDawaWeb.DistributorPagination

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Products")
     |> assign(:search, "")
     |> assign(:view_mode, "list")
     |> assign(:page_number, 1)
     |> assign(:serials_filter, "")
     |> assign(:sync_error, nil)
     |> assign(:syncing?, false)
     |> assign(:remote_counts, %{})
     |> assign(:remote_counts_loaded?, false)
     |> assign(:product, nil)}
  end

  def handle_params(params, _url, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    socket =
      socket
      |> assign(:page_number, DistributorPagination.page_number(params))
      |> assign(:search, Map.get(params, "search", socket.assigns.search))
      |> assign(:view_mode, view_mode(params, socket.assigns.view_mode))
      |> assign(
        :serials_filter,
        if(params["serials"] in ["with", "none"], do: params["serials"], else: "")
      )
      |> load_products()
      |> maybe_fetch_remote_counts(organization_id)

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new_serial, %{"gtin" => gtin}) do
    scope = socket.assigns.current_scope
    product = Manufacturing.get_product_by_gtin!(scope.organization_id, gtin)
    site = Sites.get_site!(scope.organization_id, scope.current_site_id)
    facilities = Sites.list_sites(scope.organization_id)

    socket
    |> assign(:product, product)
    |> assign(:site, site)
    |> assign(:facilities, facilities)
  end

  defp apply_action(socket, :index, _params), do: assign(socket, :product, nil)

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/manufacturer/products?#{%{search: search, view: socket.assigns.view_mode}}"
     )}
  end

  def handle_event("set_filter", %{"field" => "serials", "value" => value}, socket) do
    query =
      Enum.reject([search: socket.assigns.search, serials: value], fn {_k, v} ->
        v in [nil, ""]
      end)

    {:noreply, push_patch(socket, to: ~p"/manufacturer/products?#{query}")}
  end

  def handle_event("reset", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/manufacturer/products")}
  end

  def handle_event("set_view", %{"view" => mode}, socket) when mode in ["list", "grid"] do
    {:noreply,
     push_patch(socket,
       to: ~p"/manufacturer/products?#{%{search: socket.assigns.search, view: mode}}"
     )}
  end

  def handle_event("sync_products", _params, %{assigns: %{syncing?: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("sync_products", _params, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    {:noreply,
     socket
     |> assign(:syncing?, true)
     |> start_async(:gs1_sync, fn -> Manufacturing.sync_products(organization_id) end)}
  end

  def handle_async(:gs1_sync, {:ok, {:ok, count}}, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    {:noreply,
     socket
     |> put_flash(
       :info,
       "Synced #{count} product#{if count == 1, do: "", else: "s"} from GS1."
     )
     |> assign(:sync_error, nil)
     |> assign(:syncing?, false)
     |> load_products()
     |> start_async(:remote_counts, fn ->
       Manufacturing.remote_product_counts(organization_id)
     end)}
  end

  def handle_async(:gs1_sync, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket |> assign(:syncing?, false) |> assign(:sync_error, sync_error_message(reason))}
  end

  def handle_async(:gs1_sync, {:exit, _reason}, socket) do
    {:noreply,
     socket |> assign(:syncing?, false) |> assign(:sync_error, sync_error_message(:unavailable))}
  end

  def handle_async(:remote_counts, {:ok, {:ok, counts}}, socket) do
    rows = merge_remote_counts(socket.assigns.page_info.entries, counts)
    rows = filter_rows(rows, socket.assigns.serials_filter)
    {:noreply, socket |> assign(:remote_counts, counts) |> assign(:rows, rows)}
  end

  def handle_async(:remote_counts, _result, socket) do
    # Remote counts unavailable — keep whatever local counts are shown
    {:noreply, socket}
  end

  def handle_info({:serials_issued, :inventory, count}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, issued_stock_flash(count))
     |> push_navigate(to: ~p"/manufacturer/inventory")}
  end

  def handle_info({:serials_issued, :products, count}, socket) do
    {:noreply,
     socket
     |> assign(:remote_counts_loaded?, false)
     |> put_flash(:info, issued_stock_flash(count))
     |> push_patch(to: ~p"/manufacturer/products")}
  end

  def handle_info({:serials_issued, :aggregations, serial_count, shipper_count}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, issued_order_flash(serial_count, shipper_count))
     |> push_navigate(to: ~p"/manufacturer/aggregations")}
  end

  def handle_info({:serials_issued, :shipment, serial_count, shipper_count}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, issued_order_flash(serial_count, shipper_count))
     |> push_navigate(to: ~p"/manufacturer/shipments/new")}
  end

  def handle_info({:serial_generation_failed, reason}, socket) do
    {:noreply, put_flash(socket, :error, generation_error(reason))}
  end

  defp sync_error_message(:unconfigured),
    do: "Add your GS1 API key in organization settings, then sync again."

  defp sync_error_message(reason) when reason in [:unauthorized, :forbidden],
    do: "GS1 rejected your API key. Check it in organization settings."

  defp sync_error_message(_reason),
    do: "Thamani couldn't reach GS1. Your products are unchanged. Try again in a moment."

  defp filter_rows(rows, "with"), do: Enum.filter(rows, &(&1.serial_count > 0))
  defp filter_rows(rows, "none"), do: Enum.filter(rows, &(&1.serial_count == 0))
  defp filter_rows(rows, _), do: rows

  defp issued_stock_flash(count) do
    "#{count} primary serial#{if count == 1, do: "", else: "s"} generated."
  end

  defp issued_order_flash(serial_count, shipper_count) do
    "#{serial_count} primary serial#{if serial_count == 1, do: "", else: "s"} and " <>
      "#{shipper_count} shipper SSCC#{if shipper_count == 1, do: "", else: "s"} generated."
  end

  defp load_products(socket) do
    organization_id = socket.assigns.current_scope.organization_id

    case Manufacturing.paginate_gs1_products(organization_id,
           page: socket.assigns.page_number,
           search: socket.assigns.search
         ) do
      {:ok, page_info} ->
        remote_counts = Map.get(socket.assigns, :remote_counts, %{})
        page_info = %{page_info | entries: merge_remote_counts(page_info.entries, remote_counts)}

        socket
        |> assign(:sync_error, nil)
        |> assign(:page_info, page_info)
        |> assign(:rows, filter_rows(page_info.entries, socket.assigns[:serials_filter]))

      {:error, reason} ->
        page_info = empty_page(socket.assigns.page_number)

        socket
        |> assign(:sync_error, sync_error_message(reason))
        |> assign(:page_info, page_info)
        |> assign(:rows, [])
    end
  end

  defp maybe_fetch_remote_counts(socket, organization_id) do
    if connected?(socket) and not socket.assigns.remote_counts_loaded? do
      socket
      |> assign(:remote_counts_loaded?, true)
      |> start_async(:remote_counts, fn ->
        Manufacturing.remote_product_counts(organization_id)
      end)
    else
      socket
    end
  end

  defp merge_remote_counts(entries, remote_counts) do
    Enum.map(entries, fn %{product: product} = entry ->
      case remote_counts[product.gtin] do
        nil -> entry
        counts -> Map.merge(entry, counts)
      end
    end)
  end

  defp empty_page(page_number) do
    %{entries: [], page_number: page_number, page_size: 10, total_entries: 0, total_pages: 1}
  end

  defp view_mode(params, fallback) do
    case Map.get(params, "view", fallback) do
      mode when mode in ["list", "grid"] -> mode
      _other -> "list"
    end
  end

  defp generation_error(%Ecto.Changeset{}),
    do: "The batch details conflict with an existing batch."

  defp generation_error(:unconfigured),
    do:
      "GS1 isn't set up for your organization. Add your GS1 key in organization settings, then try again."

  defp generation_error(:unavailable),
    do: "We couldn't reach GS1. Try again in a moment."

  defp generation_error(:invalid_quantity),
    do:
      "The number of units per shipper must be positive and cannot be more than the batch quantity."

  defp generation_error(:not_found),
    do:
      "This product isn't in your GS1 account. Use \"Sync from GS1\" first, then generate serials again."

  defp generation_error(reason) when reason in [:unauthorized, :forbidden],
    do: "GS1 rejected your API key. Check it in organization settings, then try again."

  defp generation_error({:invalid, _message}),
    do: "GS1 couldn't accept the batch details. Check them and try again."

  defp generation_error(_reason),
    do: "We couldn't complete that request. Try again in a moment."

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/products"}
      crumb="Products"
    >
      <:search>
        <form id="manufacturer-product-search" phx-change="search">
          <.td_search
            name="search"
            value={@search}
            placeholder="Search GTINs or product names"
            shortcut="⌘K"
            phx-debounce="300"
          />
        </form>
      </:search>
      <.td_list_page
        title="Products"
        subtitle="GTINs registered to this organization and their serialisation activity."
      >
        <:actions>
          <.td_button
            id="sync-manufacturer-products"
            variant="secondary"
            label={if @syncing?, do: "Refreshing", else: "Refresh from GS1"}
            glyph="arrows-clockwise"
            phx-click="sync_products"
            phx-disable-with="Syncing"
            disabled={@syncing?}
            aria-busy={to_string(@syncing?)}
            tip="Pull GTINs registered to this GS1 member account into the catalogue."
            tip_align="end"
          />
        </:actions>
        <:filters>
          <.td_filter_menu
            id="products"
            field="serials"
            label="Serials"
            value={@serials_filter}
            options={[{"", "All"}, {"with", "Has serials"}, {"none", "No serials yet"}]}
          />
          <.td_toolbar_count
            id="manufacturer-products-count"
            shown={length(@rows)}
            total={@page_info.total_entries}
            noun={if @page_info.total_entries == 1, do: "product", else: "products"}
          />
        </:filters>

        <div :if={@sync_error} id="products-sync-error" class="td-ban is-danger mb-3">
          <.td_icon name="warning-circle" class="size-4" />
          <span><b>Sync failed.</b> {@sync_error}</span>
          <.td_button
            id="retry-sync-products"
            label={if @syncing?, do: "Syncing", else: "Retry sync"}
            glyph="arrows-clockwise"
            phx-click="sync_products"
            phx-disable-with="Syncing"
            disabled={@syncing?}
            aria-busy={to_string(@syncing?)}
          />
        </div>

        <div :if={@rows == []} id="manufacturer-products-empty" class="td-pad td-empty-wrap">
          <div class="td-card td-empty-card">
            <%= if @search != "" or @serials_filter != "" do %>
              <p class="td-empty-title">Nothing matches</p>
              <p class="td-note">Try a different search, or clear the filters.</p>
              <.td_button id="products-clear-filters" phx-click="reset" label="Clear filters" />
            <% else %>
              <p class="td-empty-title">No products yet</p>
              <p class="td-note">
                <%= if @syncing? do %>
                  Refreshing products from GS1.
                <% else %>
                  Products are loaded directly from your GS1 member account. Refresh to check for newly registered GTINs.
                <% end %>
              </p>
              <.td_button
                id="products-empty-sync"
                variant="primary"
                glyph="arrows-clockwise"
                label={if @syncing?, do: "Refreshing", else: "Refresh from GS1"}
                phx-click="sync_products"
                phx-disable-with="Syncing"
                disabled={@syncing?}
                aria-busy={to_string(@syncing?)}
              />
            <% end %>
          </div>
        </div>

        <div class="td-list-table" hidden={@rows == []}>
          <table class="td-rows" id="manufacturer-products">
            <thead>
              <tr>
                <th>Product</th>
                <th>GTIN</th>
                <th class="is-num">Serials</th>
                <th class="is-num">Shipper SSCCs</th>
                <th>Status</th>
                <th><span class="sr-only">Actions</span></th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={%{product: product, serial_count: serials, sscc_count: ssccs} <- @rows}
                id={"manufacturer-product-#{product.id}"}
              >
                <td>
                  <.link
                    id={"product-#{product.id}-open"}
                    class="td-link"
                    navigate={
                      ~p"/manufacturer/products/#{product.id}?#{%{return_to: "/manufacturer/products"}}"
                    }
                  >
                    {product.name}
                  </.link>
                  <span :if={product.description} class="td-sub td-s12">{product.description}</span>
                </td>
                <td>
                  <.td_pid id={"product-#{product.id}-gtin"} label={product.gtin} mono>
                    <:peek>
                      <.td_peek kind="GTIN" title={product.gtin} subtitle={product.name} mono>
                        <:row :if={product.brand_owner} label="Brand owner">
                          {product.brand_owner}
                        </:row>
                        <:row label="Serials">{serials}</:row>
                        <:row label="Shipper SSCCs">{ssccs}</:row>
                        <:row label="Added">
                          {ThamaniDawaWeb.TimeFormat.date(product.inserted_at)}
                        </:row>
                        <:action>
                          <.td_button
                            :if={serials > 0}
                            navigate={~p"/manufacturer/products/#{product.gtin}/serials"}
                            label="View serials"
                          />
                          <.td_button
                            patch={~p"/manufacturer/products/#{product.gtin}/serials/new"}
                            label="Generate serials"
                          />
                        </:action>
                      </.td_peek>
                    </:peek>
                  </.td_pid>
                </td>
                <td class="is-num">
                  <span id={"product-#{product.id}-serial-count"}>{serials}</span>
                </td>
                <td class="is-num">
                  <.link
                    id={"product-#{product.id}-ssccs"}
                    navigate={~p"/manufacturer/products/#{product.gtin}/ssccs"}
                    class="td-link"
                  >
                    <span id={"product-#{product.id}-sscc-count"}>{ssccs}</span>
                  </.link>
                </td>
                <td><.td_badge tone="success" label="Active" /></td>
                <td class="td-row-actions">
                  <.td_button
                    :if={serials > 0}
                    id={"product-#{product.id}-serials"}
                    label="View serials"
                    navigate={~p"/manufacturer/products/#{product.gtin}/serials"}
                    tip="Open the batches and DataMatrix codes already issued for this GTIN."
                    tip_align="end"
                  />
                  <.td_button
                    id={"product-#{product.id}-add-serial"}
                    label="Generate serials"
                    patch={~p"/manufacturer/products/#{product.gtin}/serials/new"}
                    tip="Issue a GS1 batch and DataMatrix serials. You will set quantity, dates, and facility."
                    tip_align="end"
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.td_list_page>

      <.pagination
        :if={@page_info.total_entries > 0}
        page={@page_info}
        path={~p"/manufacturer/products?#{%{search: @search, view: @view_mode}}"}
      />

      <.td_modal
        :if={@live_action == :new_serial}
        id="manufacturer-serial-modal"
        show
        class="is-tall"
        title="Generate serials"
        on_cancel={JS.patch(~p"/manufacturer/products")}
      >
        <:body>
          <.live_component
            module={ThamaniDawaWeb.ManufacturerProductLive.SerialWizard}
            id={"serial-wizard-#{@product.id}"}
            product={@product}
            organization_id={@current_scope.organization_id}
            site={@site}
            facilities={@facilities}
          />
        </:body>
      </.td_modal>
    </Layouts.manufacturer_shell>
    """
  end
end
