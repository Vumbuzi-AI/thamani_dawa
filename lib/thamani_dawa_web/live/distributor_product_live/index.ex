defmodule ThamaniDawaWeb.DistributorProductLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Products
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Suppliers
  alias ThamaniDawaWeb.DistributorPagination

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    sites = Sites.list_sites(organization_id)

    warehouse_ids =
      sites |> Enum.filter(&(&1.site_type == :warehouse and &1.is_active)) |> Enum.map(& &1.id)

    {:ok,
     socket
     |> assign(:view, "products")
     |> assign(:search, "")
     |> assign(:page_number, 1)
     |> assign(:products_by_id, Map.new(Products.list_products(organization_id), &{&1.id, &1}))
     |> assign(:sites_by_id, Map.new(sites, &{&1.id, &1}))
     |> assign(:warehouse_ids, warehouse_ids)
     |> assign(
       :suppliers_by_id,
       Map.new(Suppliers.list_suppliers(organization_id), &{&1.id, &1})
     )
     |> reload_products()}
  end

  def handle_params(params, _url, socket) do
    view = if params["view"] == "batches", do: "batches", else: "products"

    form =
      if socket.assigns.live_action == :new do
        to_form(Product.changeset(%Product{}, %{}), as: :product)
      else
        nil
      end

    {:noreply,
     socket
     |> assign(:view, view)
     |> assign(:search, Map.get(params, "search", ""))
     |> assign(:page_number, DistributorPagination.page_number(params))
     |> assign(:form, form)
     |> reload_view()}
  end

  def handle_event("validate", %{"product" => attrs}, socket) do
    changeset = Map.put(Product.changeset(%Product{}, attrs), :action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset, as: :product))}
  end

  def handle_event("save", %{"product" => attrs}, socket) do
    case Products.create_product(socket.assigns.current_scope.organization_id, attrs) do
      {:ok, product} ->
        {:noreply,
         socket
         |> put_flash(:info, "Product added.")
         |> assign(:products_by_id, Map.put(socket.assigns.products_by_id, product.id, product))
         |> reload_products()
         |> push_patch(to: ~p"/distributor/products")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :product))}
    end
  end

  def handle_event("set_view", %{"view" => view}, socket) when view in ["products", "batches"] do
    {:noreply, socket |> assign(:view, view) |> assign(:page_number, 1) |> reload_view()}
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> assign(:page_number, 1) |> reload_view()}
  end

  defp reload_view(%{assigns: %{view: "batches"}} = socket), do: reload_batches(socket)
  defp reload_view(socket), do: reload_products(socket)

  defp reload_products(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    search = String.downcase(String.trim(socket.assigns.search))
    products = Products.list_products(organization_id)

    summary =
      Batches.stock_summary_by_product(
        organization_id,
        Enum.map(products, & &1.id),
        socket.assigns.warehouse_ids
      )

    rows =
      products
      |> Enum.filter(&matches_product?(&1, search))
      |> Enum.map(fn product ->
        stock = Map.get(summary, product.id, %{batch_count: 0, total_remaining: 0})

        %{
          id: product.id,
          product: product,
          batch_count: stock.batch_count,
          remaining: stock.total_remaining
        }
      end)

    page_info = DistributorPagination.page(rows, socket.assigns.page_number)

    socket
    |> assign(:page_info, page_info)
    |> stream(:products, page_info.entries, reset: true)
  end

  defp reload_batches(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    search = String.downcase(String.trim(socket.assigns.search))

    batches =
      organization_id
      |> Batches.list_batches()
      |> Enum.filter(fn batch ->
        product = socket.assigns.products_by_id[batch.product_id]

        batch.site_id in socket.assigns.warehouse_ids and
          (search == "" or
             Enum.any?(
               [
                 product && product.generic_name,
                 product && product.brand_name,
                 batch.gtin,
                 batch.batch_no
               ],
               &(is_binary(&1) and String.contains?(String.downcase(&1), search))
             ))
      end)

    page_info = DistributorPagination.page(batches, socket.assigns.page_number)

    socket
    |> assign(:page_info, page_info)
    |> stream(:batches, page_info.entries, reset: true)
  end

  defp pagination_path("products", search) do
    params = if search == "", do: %{}, else: %{"search" => search}
    ~p"/distributor/products?#{params}"
  end

  defp pagination_path("batches", search) do
    params =
      %{"view" => "batches"}
      |> then(fn params ->
        if search == "", do: params, else: Map.put(params, "search", search)
      end)

    ~p"/distributor/products?#{params}"
  end

  defp matches_product?(_product, ""), do: true

  defp matches_product?(product, search) do
    Enum.any?(
      [product.generic_name, product.brand_name, product.gtin, product.category],
      &(is_binary(&1) and String.contains?(String.downcase(&1), search))
    )
  end

  defp product_name(product), do: product.generic_name || product.brand_name || "(unnamed)"
  defp site_name(nil), do: "—"
  defp site_name(site), do: site.name
  defp money(nil), do: "—"
  defp money(value), do: "KES #{value}"

  defp date_or_dash(nil), do: "—"
  defp date_or_dash(date), do: Calendar.strftime(date, "%d %b %Y")
  defp unit_label("H87"), do: "piece(s)"
  defp unit_label("U2"), do: "tablet(s)"
  defp unit_label("C62"), do: "unit(s)"
  defp unit_label("KGM"), do: "kilogram(s)"
  defp unit_label(nil), do: "unit(s)"
  defp unit_label(unit), do: if(String.ends_with?(unit, "(s)"), do: unit, else: "#{unit}(s)")

  defp quantity_with_unit(quantity, product),
    do: "#{quantity} #{unit_label(product && product.uom)}"

  defp batch_status(batch) do
    days = Date.diff(batch.expiry_date, Date.utc_today())

    cond do
      days < 0 -> :expired
      days <= 90 -> :near_expiry
      batch.approver_id && batch.remaining_quantity > 0 -> :active
      true -> :pending
    end
  end

  defp available_quantity(batch),
    do:
      if(Date.compare(batch.expiry_date, Date.utc_today()) == :gt,
        do: batch.remaining_quantity,
        else: 0
      )

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/products"}
    >
      <.header icon={if @view == "products", do: "hero-cube", else: "hero-archive-box"}>
        {if @view == "products", do: "Products", else: "All batches"}
        <:subtitle>
          {if @view == "products",
            do: "Maintain the GTIN-identified items your warehouses distribute.",
            else:
              "Review inventory batches across your warehouses, including expiry and remaining stock."}
        </:subtitle>
        <:actions>
          <.button
            :if={@view == "products"}
            id="add-distributor-product"
            variant="primary"
            patch={~p"/distributor/products/new"}
          >
            <.icon name="hero-plus" class="size-4" /> Add product
          </.button>
        </:actions>
        <:toolbar>
          <.tab_group>
            <:tab
              id="distributor-products-tab"
              active={@view == "products"}
              phx_click="set_view"
              phx_value_view="products"
            >
              Products
            </:tab>
            <:tab
              id="distributor-batches-tab"
              active={@view == "batches"}
              phx_click="set_view"
              phx_value_view="batches"
            >
              All batches
            </:tab>
          </.tab_group>
          <form phx-change="search" id="distributor-product-search" class="flex-1">
            <.search_input
              name="search"
              value={@search}
              placeholder={
                if @view == "products",
                  do: "Search by product, GTIN, or category",
                  else: "Search by product, GTIN, or batch number"
              }
            />
          </form>
        </:toolbar>
      </.header>

      <.modal
        :if={@live_action == :new}
        id="distributor-product-modal"
        show
        on_cancel={JS.patch(~p"/distributor/products")}
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest">Add product</h2>
        <.form
          for={@form}
          id="distributor-product-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-4"
        >
          <div class="grid gap-x-4 sm:grid-cols-2">
            <.input field={@form[:generic_name]} label="Generic name" />
            <.input field={@form[:brand_name]} label="Brand name" />
            <.input field={@form[:gtin]} label="GTIN" required />
            <.input
              field={@form[:uom]}
              type="select"
              label="Base inventory unit"
              prompt="Select unit"
              options={[
                {"Piece (H87)", "H87"},
                {"Tablet (U2)", "U2"},
                {"Unit (C62)", "C62"},
                {"Kilogram (KGM)", "KGM"}
              ]}
              required
            />
            <.input field={@form[:category]} label="Category" />
            <.input field={@form[:manufacturer]} label="Manufacturer" />
            <.input field={@form[:price]} type="number" label="Unit price (KSh)" min="0" required />
            <.input field={@form[:reorder_level]} type="number" label="Reorder level" min="0" />
          </div>
          <.button class="mt-2" variant="primary">Add product</.button>
        </.form>
      </.modal>

      <div :if={@view == "products"} class="mt-5">
        <.table
          id="distributor-products"
          rows={@streams.products}
          row_click={fn {_id, row} -> JS.navigate(~p"/distributor/products/#{row.product.id}") end}
        >
          <:col :let={{_id, product}} label="Product">
            <span class="font-medium text-thamani-forest">
              {product_name(product.product)}
            </span>
          </:col>
          <:col :let={{_id, row}} label="Category">{row.product.category || "—"}</:col>
          <:col :let={{_id, row}} label="Brand">{row.product.brand_name || "—"}</:col>
          <:col :let={{_id, row}} label="Manufacturer">{row.product.manufacturer || "—"}</:col>
          <:col :let={{_id, row}} label="Price">{money(row.product.price)}</:col>
          <:col :let={{_id, row}} label="Batches">{row.batch_count}</:col>
          <:col :let={{_id, row}} label="On hand">
            {quantity_with_unit(row.remaining, row.product)}
          </:col>
          <:col :let={{_id, row}} label="Status">
            <.status_badge status={if row.product.is_active, do: :active, else: :inactive} />
          </:col>
          <:col :let={{_id, row}} label="GTIN">
            <span class="font-mono">{row.product.gtin}</span>
          </:col>
          <:col :let={{_id, row}} label="Unit">{unit_label(row.product.uom)}</:col>
          <:col :let={{_id, row}} label="Reorder level">{row.product.reorder_level || "—"}</:col>
          <:empty_state>
            <.blank_state icon="hero-cube" title="No distributor products yet">
              {if @search == "",
                do: "Add a GTIN-identified product before receiving stock.",
                else: "Try a different product name, GTIN, or category."}
            </.blank_state>
          </:empty_state>
        </.table>
      </div>

      <div :if={@view == "batches"} class="mt-5">
        <.table
          id="distributor-batches"
          rows={@streams.batches}
          row_click={fn {_id, batch} -> JS.navigate(~p"/distributor/batches/#{batch.id}") end}
        >
          <:col :let={{_id, batch}} label="Product">
            {product_name(@products_by_id[batch.product_id])}
          </:col>
          <:col :let={{_id, batch}} label="Batch">
            <span class="font-mono">{batch.batch_no}</span>
          </:col>
          <:col :let={{_id, batch}} label="Warehouse">{site_name(@sites_by_id[batch.site_id])}</:col>
          <:col :let={{_id, batch}} label="Expiry">{date_or_dash(batch.expiry_date)}</:col>
          <:col :let={{_id, batch}} label="Available">
            {quantity_with_unit(available_quantity(batch), @products_by_id[batch.product_id])}
          </:col>
          <:col :let={{_id, batch}} label="Status">
            <.status_badge status={batch_status(batch)} />
          </:col>
          <:empty_state>
            <.blank_state
              icon="hero-archive-box"
              title={
                if @search == "", do: "No stock batches yet", else: "No batches match your search"
              }
            >
              {if @search == "",
                do: "Received stock batches will appear here after inventory is checked in.",
                else: "Try another product name, GTIN, or batch number."}
            </.blank_state>
          </:empty_state>
        </.table>
      </div>
      <.pagination page={@page_info} path={pagination_path(@view, @search)} />
    </Layouts.distributor_shell>
    """
  end
end
