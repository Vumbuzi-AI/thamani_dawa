defmodule ThamaniDawaWeb.ManufacturerProductLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Distributor.Billing
  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Manufacturing.Product
  alias ThamaniDawa.Sites
  alias ThamaniDawaWeb.DistributorPagination

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Products")
     |> assign(:search, "")
     |> assign(:view_mode, "list")
     |> assign(:page_number, 1)
     |> assign(:product, nil)}
  end

  def handle_params(params, _url, socket) do
    socket =
      socket
      |> assign(:page_number, DistributorPagination.page_number(params))
      |> assign(:search, Map.get(params, "search", socket.assigns.search))
      |> assign(:view_mode, view_mode(params, socket.assigns.view_mode))
      |> load_products()

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    product = %Product{}

    socket
    |> assign(:product, product)
    |> assign(:form, to_form(Manufacturing.change_product(product), as: :product))
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

  def handle_event("reset", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/manufacturer/products")}
  end

  def handle_event("set_view", %{"view" => mode}, socket) when mode in ["list", "grid"] do
    {:noreply,
     push_patch(socket,
       to: ~p"/manufacturer/products?#{%{search: socket.assigns.search, view: mode}}"
     )}
  end

  def handle_event("sync_products", _params, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    case Manufacturing.sync_products(organization_id) do
      {:ok, count} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Synced #{count} product#{if count == 1, do: "", else: "s"} from GS1."
         )
         |> load_products()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't sync products: #{inspect(reason)}")}
    end
  end

  def handle_event("validate", %{"product" => params}, socket) do
    changeset =
      socket.assigns.product
      |> Manufacturing.change_product(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :product))}
  end

  def handle_event("save", %{"product" => params}, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    case Manufacturing.create_product(organization_id, params) do
      {:ok, product} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{product.name} added.")
         |> push_patch(to: ~p"/manufacturer/products")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :product))}
    end
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

  defp issued_stock_flash(count) do
    "#{count} primary serial#{if count == 1, do: "", else: "s"} generated."
  end

  defp issued_order_flash(serial_count, shipper_count) do
    "#{serial_count} primary serial#{if serial_count == 1, do: "", else: "s"} and " <>
      "#{shipper_count} shipper SSCC#{if shipper_count == 1, do: "", else: "s"} generated."
  end

  defp load_products(socket) do
    organization_id = socket.assigns.current_scope.organization_id

    page_info =
      Manufacturing.paginate_products_with_counts(organization_id,
        page: socket.assigns.page_number,
        search: socket.assigns.search
      )

    counts = Manufacturing.generation_counts(organization_id)
    usage = Billing.active_usage(organization_id)

    socket
    |> assign(:page_info, page_info)
    |> assign(:rows, page_info.entries)
    |> assign(:number_generated, counts.serials + counts.ssccs)
    |> assign(:maximum, maximum(usage))
  end

  defp maximum(%{quantity_limit: nil}), do: "Unlimited"
  defp maximum(%{quantity_limit: limit}) when is_integer(limit), do: limit
  defp maximum(_usage), do: 0

  defp view_mode(params, fallback) do
    case Map.get(params, "view", fallback) do
      mode when mode in ["list", "grid"] -> mode
      _other -> "list"
    end
  end

  defp generation_error(%Ecto.Changeset{}),
    do: "The batch details conflict with an existing batch."

  defp generation_error(:unconfigured),
    do: "The GS1 member API is not configured. No serials were saved."

  defp generation_error(:unavailable),
    do: "The GS1 member API is unavailable. No serials were saved."

  defp generation_error(:invalid_quantity),
    do: "The shipper quantity must be a positive integer no greater than the primary quantity."

  defp generation_error(:not_found),
    do:
      "This GTIN isn't registered under your GS1 member account. Use \"Sync from GS1\" to import your products before generating serials."

  defp generation_error(:unauthorized),
    do: "GS1 rejected the API credentials. Check the organization's GS1 API key."

  defp generation_error(:forbidden),
    do:
      "This GS1 account isn't allowed to issue SSCCs, which make-to-order requires. Use make-to-stock, or contact GS1 Kenya to enable SSCC API access."

  defp generation_error(reason), do: "Serial generation failed: #{inspect(reason)}"

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/products"}
      crumb="Products"
    >
      <.td_list_page
        title="Products"
        subtitle="GTINs registered to this organization and their serialisation activity."
      >
        <:actions>
          <.td_button id="sync-manufacturer-products" variant="secondary" label="Sync from GS1" phx-click="sync_products" />
          <.td_button
            id="add-manufacturer-product"
            variant="primary"
            label="Add product"
            patch={~p"/manufacturer/products/new"}
          />
        </:actions>
        <:filters>
          <div class="td-stats">
            <.td_stat id="manufacturer-number-generated" caption="Number generated" value={@number_generated} />
            <.td_stat id="manufacturer-maximum" caption="Maximum" value={@maximum} />
          </div>
          <form id="manufacturer-product-search" phx-change="search">
            <.td_search
              name="search"
              value={@search}
              placeholder="Search GTIN, brand or description"
              phx-debounce="300"
            />
          </form>
          <.td_segmented>
            <.td_segment
              id="manufacturer-list-view"
              label="List"
              active={@view_mode == "list"}
              phx-click="set_view"
              phx-value-view="list"
            />
            <.td_segment
              id="manufacturer-grid-view"
              label="Grid"
              active={@view_mode == "grid"}
              phx-click="set_view"
              phx-value-view="grid"
            />
          </.td_segmented>
          <.td_button id="reset-manufacturer-products" variant="secondary" label="Reset" phx-click="reset" />
        </:filters>

        <.td_data_table
          :if={@view_mode == "list"}
          id="manufacturer-products"
          rows={@rows}
          row_id={fn %{product: product} -> "manufacturer-product-#{product.id}" end}
        >
          <:col :let={%{product: product}} label="GTIN">
            <span class="td-kv-value is-mono">{product.gtin}</span>
          </:col>
          <:col :let={%{product: product}} label="Product">{product.name}</:col>
          <:col :let={%{product: product}} label="Description">{product.description || "—"}</:col>
          <:col :let={%{product: product}} label="Created at">
            {Calendar.strftime(product.inserted_at, "%d %b %Y")}
          </:col>
          <:col :let={%{product: product, sscc_count: count}} label="SSCC">
            {count}
            <.td_button
              id={"product-#{product.id}-ssccs"}
              variant="secondary"
              label="View"
              navigate={~p"/manufacturer/products/#{product.gtin}/ssccs"}
            />
          </:col>
          <:col :let={%{product: product, serial_count: count}} label="Serials">
            {count}
            <.td_button
              id={"product-#{product.id}-serials"}
              variant="secondary"
              label="View"
              navigate={~p"/manufacturer/products/#{product.gtin}/serials"}
            />
          </:col>
          <:action :let={%{product: product}}>
            <.td_button
              id={"product-#{product.id}-add-serial"}
              variant="primary"
              label="Serial"
              patch={~p"/manufacturer/products/#{product.gtin}/serials/new"}
            />
          </:action>
          <:empty>
            <.td_empty
              title="No products found"
              hint="Add or sync a GTIN to start generating primary serials."
            />
          </:empty>
        </.td_data_table>

        <div
          :if={@view_mode == "grid"}
          id="manufacturer-products-grid"
          class="td-stats"
        >
          <article :for={row <- @rows} id={"manufacturer-product-card-#{row.product.id}"} class="td-stat">
            <span class="td-kv-value is-mono">{row.product.gtin}</span>
            <span class="td-stat-value">{row.product.name}</span>
            <span class="td-stat-sub">{row.product.description || "No description"}</span>
            <.td_key_value label="SSCC" value={row.sscc_count} />
            <.td_key_value label="Serials" value={row.serial_count} />
            <.td_button
              variant="primary"
              label="Serial"
              patch={~p"/manufacturer/products/#{row.product.gtin}/serials/new"}
            />
          </article>
          <.td_empty :if={@rows == []} title="No products found" hint="Add or sync a GTIN to start generating primary serials." />
        </div>
      </.td_list_page>

      <.pagination
        :if={@page_info.total_entries > 0}
        page={@page_info}
        path={~p"/manufacturer/products?#{%{search: @search, view: @view_mode}}"}
      />

      <.td_overlay_form
        :if={@live_action == :new}
        id="manufacturer-product"
        title="Add product"
        submit="Save product"
        on_cancel={JS.patch(~p"/manufacturer/products")}
      >
        <.form
          for={@form}
          id="manufacturer-product-form"
          phx-change="validate"
          phx-submit="save"
        >
          <.td_input field={@form[:gtin]} label="GTIN" placeholder="8 to 14 digits" required />
          <.td_input field={@form[:name]} label="Product name" required />
          <.td_input field={@form[:description]} label="Description" />
          <.td_input field={@form[:brand_owner]} label="Brand owner" />
        </.form>
      </.td_overlay_form>

      <.td_modal
        :if={@live_action == :new_serial}
        id="manufacturer-serial-modal"
        show
        title="Generate primary serials"
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
