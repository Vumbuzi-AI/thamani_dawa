defmodule ThamaniDawaWeb.PharmacyStockLive do
  @moduledoc """
  Read-only view of batch/product stock. Admins see every site in the
  organization, with a site filter to narrow down. Non-admin staff
  (pharmacist, lab technician, pharma_lab) are restricted to the sites
  they're assigned to (`user.sites`) — both the underlying data and the
  Site filter's options are limited to that set, so they can never browse
  or filter into another site's stock. Nothing here mutates a batch —
  receiving/dispensing stay on `ReceiveStockLive`/`PrescriptionLive`, both
  still site-locked as before.

  Two views, toggled without a full page navigation: "Products" (paginated,
  one row per product with a batch/stock roll-up) and "Batches" (paginated,
  the flat batch-level table this screen originally was). Clicking a product
  navigates to `PharmacyStockProductLive`, which lists that product's
  batches; clicking a batch there (or in the flat batches view) navigates to
  `PharmacyStockBatchLive`, which shows who has drawn stock from it.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Batches
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Suppliers

  @default_filters %{site: "", status: ""}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    org_id = scope.organization_id
    sites = if Scope.admin?(scope), do: Sites.list_sites(org_id), else: scope.user.sites
    site_ids = if Scope.admin?(scope), do: nil, else: Enum.map(sites, & &1.id)

    {:ok,
     socket
     |> assign(:products_by_id, org_id |> Products.list_products() |> Map.new(&{&1.id, &1}))
     |> assign(:sites_by_id, Map.new(sites, &{&1.id, &1}))
     |> assign(:suppliers_by_id, org_id |> Suppliers.list_suppliers() |> Map.new(&{&1.id, &1}))
     |> assign(:site_options, Enum.map(sites, &{&1.name, &1.id}))
     |> assign(:allowed_site_ids, site_ids)
     |> assign(:search, "")
     |> assign(:filters, @default_filters)
     |> assign(:view, "products")
     |> assign(:page, 1)
     |> assign(:page_info, %{page_number: 1, total_pages: 1, total_entries: 0, page_size: 1})
     |> reload()}
  end

  def handle_event("set_view", %{"view" => view}, socket) do
    {:noreply,
     socket
     |> assign(:view, view)
     |> assign(:page, 1)
     |> reload()}
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> assign(:page, 1) |> reload()}
  end

  def handle_event("apply_filters", %{"filters" => filter_params}, socket) do
    filters = %{
      site:
        sanitize_site_filter(Map.get(filter_params, "site", ""), socket.assigns.allowed_site_ids),
      status: Map.get(filter_params, "status", "")
    }

    {:noreply, socket |> assign(:filters, filters) |> assign(:page, 1) |> reload()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, socket |> assign(:filters, @default_filters) |> assign(:page, 1) |> reload()}
  end

  def handle_event("clear_chip", %{"field" => "site"}, socket) do
    {:noreply,
     socket
     |> assign(:filters, %{socket.assigns.filters | site: ""})
     |> assign(:page, 1)
     |> reload()}
  end

  def handle_event("clear_chip", %{"field" => "status"}, socket) do
    {:noreply,
     socket
     |> assign(:filters, %{socket.assigns.filters | status: ""})
     |> assign(:page, 1)
     |> reload()}
  end

  def handle_event("go_to_page", %{"page" => page}, socket) do
    {:noreply, socket |> assign(:page, String.to_integer(page)) |> reload()}
  end

  defp reload(socket) do
    case socket.assigns.view do
      "products" -> reload_products(socket)
      "batches" -> reload_batches(socket)
    end
  end

  defp reload_products(socket) do
    org_id = socket.assigns.current_scope.organization_id
    page_result = Products.list_products_paginated(org_id, socket.assigns.page)

    products =
      page_result.entries
      |> filter_products_by_search(socket.assigns.search)

    summary =
      Batches.stock_summary_by_product(
        org_id,
        Enum.map(products, & &1.id),
        socket.assigns.allowed_site_ids
      )

    rows =
      Enum.map(products, fn product ->
        %{
          id: product.id,
          product: product,
          batch_count: get_in(summary, [product.id, :batch_count]) || 0,
          total_remaining: get_in(summary, [product.id, :total_remaining]) || 0
        }
      end)

    socket
    |> assign(:page_info, page_result)
    |> stream(:products, rows, reset: true)
  end

  defp reload_batches(socket) do
    org_id = socket.assigns.current_scope.organization_id

    page_result =
      Batches.list_batches_paginated(org_id, socket.assigns.page, socket.assigns.allowed_site_ids)

    filtered =
      page_result.entries
      |> filter_batches_by_search(socket.assigns.search, socket.assigns.products_by_id)
      |> filter_by_site(socket.assigns.filters.site)
      |> filter_by_status(socket.assigns.filters.status)
      |> Enum.sort_by(& &1.expiry_date, Date)

    socket
    |> assign(:page_info, page_result)
    |> stream(:batches, filtered, reset: true)
  end

  defp filter_products_by_search(products, ""), do: products

  defp filter_products_by_search(products, search) do
    search = String.downcase(String.trim(search))

    Enum.filter(products, fn product ->
      [product.generic_name, product.brand_name, product.gtin, product.category]
      |> Enum.filter(& &1)
      |> Enum.any?(&String.contains?(String.downcase(&1), search))
    end)
  end

  defp filter_batches_by_search(batches, "", _products_by_id), do: batches

  defp filter_batches_by_search(batches, search, products_by_id) do
    search = String.downcase(String.trim(search))

    Enum.filter(batches, fn batch ->
      product = products_by_id[batch.product_id]

      [product && product.generic_name, product && product.brand_name, batch.gtin, batch.batch_no]
      |> Enum.filter(& &1)
      |> Enum.any?(&String.contains?(String.downcase(&1), search))
    end)
  end

  defp filter_by_site(batches, ""), do: batches

  defp filter_by_site(batches, site_id_str),
    do: Enum.filter(batches, &(to_string(&1.site_id) == site_id_str))

  defp sanitize_site_filter(site_id_str, nil), do: site_id_str
  defp sanitize_site_filter("", _allowed_site_ids), do: ""

  defp sanitize_site_filter(site_id_str, allowed_site_ids) do
    if String.to_integer(site_id_str) in allowed_site_ids, do: site_id_str, else: ""
  end

  defp filter_by_status(batches, ""), do: batches
  defp filter_by_status(batches, "active"), do: Enum.filter(batches, &(!is_nil(&1.approver_id)))
  defp filter_by_status(batches, "pending"), do: Enum.filter(batches, &is_nil(&1.approver_id))

  defp active_filter_count(filters) do
    Enum.count([filters.site != "", filters.status != ""], & &1)
  end

  defp filter_chips(filters, sites_by_id) do
    [
      filters.site != "" &&
        %{label: "Site: #{site_label(filters.site, sites_by_id)}", field: "site"},
      filters.status != "" &&
        %{label: "Status: #{Phoenix.Naming.humanize(filters.status)}", field: "status"}
    ]
    |> Enum.filter(& &1)
  end

  defp site_label(site_id_str, sites_by_id) do
    case sites_by_id[String.to_integer(site_id_str)] do
      nil -> site_id_str
      site -> site.name
    end
  end

  defp product_name(nil), do: "(unknown product)"
  defp product_name(product), do: product.generic_name || product.brand_name || "(unnamed)"

  defp site_name(nil), do: "(unknown site)"
  defp site_name(site), do: site.name

  defp supplier_name(nil), do: "—"
  defp supplier_name(supplier), do: supplier.name

  defp stock_subtitle(nil), do: "Every batch across every site in your organization — read-only."
  defp stock_subtitle(_site_ids), do: "Every batch across your assigned sites — read-only."

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/pharmacy/stock"
    >
      <.header icon="hero-cube">
        Organization stock
        <:subtitle>{stock_subtitle(@allowed_site_ids)}</:subtitle>
        <:toolbar>
          <.tab_group>
            <:tab
              id="products-tab"
              active={@view == "products"}
              phx_click="set_view"
              phx_value_view="products"
            >
              Products
            </:tab>
            <:tab
              id="batches-tab"
              active={@view == "batches"}
              phx_click="set_view"
              phx_value_view="batches"
            >
              All batches
            </:tab>
          </.tab_group>

          <form phx-change="search" class="flex-1" id="search-form">
            <.search_input
              name="search"
              value={@search}
              placeholder={
                if @view == "products",
                  do: "Search by product, GTIN, or category",
                  else: "Search by product, GTIN, or batch no."
              }
            />
          </form>

          <.filter_drawer
            :if={@view == "batches"}
            id="stock-filters"
            title="Filter stock"
            apply_event="apply_filters"
            active_count={active_filter_count(@filters)}
          >
            <:group label="Site">
              <.input
                type="select"
                name="filters[site]"
                value={@filters.site}
                options={@site_options}
                prompt="All sites"
              />
            </:group>
            <:group label="Status">
              <.input
                type="select"
                name="filters[status]"
                value={@filters.status}
                options={[{"Active", "active"}, {"Pending receipt", "pending"}]}
                prompt="All statuses"
              />
            </:group>
            <:chip
              :for={chip <- filter_chips(@filters, @sites_by_id)}
              label={chip.label}
              clear={JS.push("clear_chip", value: %{"field" => chip.field})}
            />
          </.filter_drawer>
        </:toolbar>
      </.header>

      <div :if={@view == "products"}>
        <.table
          id="products"
          rows={@streams.products}
          row_click={fn {_id, row} -> JS.navigate(~p"/pharmacy/stock/products/#{row.product.id}") end}
        >
          <:col :let={{_id, row}} label="Product">{product_name(row.product)}</:col>
          <:col :let={{_id, row}} label="Category">{row.product.category || "—"}</:col>
          <:col :let={{_id, row}} label="GTIN">{row.product.gtin}</:col>
          <:col :let={{_id, row}} label="Price">
            {row.product.price && "KES #{row.product.price}"}
          </:col>
          <:col :let={{_id, row}} label="Batches">{row.batch_count}</:col>
          <:col :let={{_id, row}} label="Remaining">{row.total_remaining}</:col>
          <:empty_state>
            <.blank_state
              icon="hero-cube"
              title={if @search != "", do: "No products match your search", else: "No products yet"}
            >
              {if @search != "",
                do: "Try a different search term.",
                else: "Products with stock will appear here."}
            </.blank_state>
          </:empty_state>
        </.table>
      </div>

      <div :if={@view == "batches"}>
        <.table
          id="stock"
          rows={@streams.batches}
          row_click={fn {_id, batch} -> JS.navigate(~p"/pharmacy/stock/batches/#{batch.id}") end}
        >
          <:col :let={{_id, batch}} label="Product">
            {product_name(@products_by_id[batch.product_id])}
          </:col>
          <:col :let={{_id, batch}} label="Site">{site_name(@sites_by_id[batch.site_id])}</:col>
          <:col :let={{_id, batch}} label="Batch no.">{batch.batch_no}</:col>
          <:col :let={{_id, batch}} label="Serial">{batch.serial || "—"}</:col>
          <:col :let={{_id, batch}} label="Manufacture date">{batch.manufacture_date || "—"}</:col>
          <:col :let={{_id, batch}} label="Expiry">{batch.expiry_date}</:col>
          <:col :let={{_id, batch}} label="Remaining">{batch.remaining_quantity}</:col>
          <:col :let={{_id, batch}} label="Supplier">
            {supplier_name(@suppliers_by_id[batch.supplier_id])}
          </:col>
          <:col :let={{_id, batch}} label="Status">
            <.status_badge status={if batch.approver_id, do: :active, else: :pending_receipt} />
          </:col>
          <:empty_state>
            <.blank_state
              icon="hero-cube"
              title={
                if @search != "" or active_filter_count(@filters) > 0,
                  do: "No batches match your search or filters",
                  else: "No stock yet"
              }
            >
              {if @search != "" or active_filter_count(@filters) > 0,
                do: "Try a different search term, or clear the applied filters.",
                else: "Batches dispatched to any site will appear here."}
            </.blank_state>
          </:empty_state>
        </.table>
      </div>

      <div class="mt-8 flex items-center justify-between border-t border-slate-200 pt-6">
        <p class="text-sm text-slate-500">
          Showing page <span class="font-medium text-slate-900">{@page_info.page_number}</span>
          of <span class="font-medium text-slate-900">{max(@page_info.total_pages, 1)}</span>
          (<span class="font-medium text-slate-900">{@page_info.total_entries}</span>
          total)
        </p>
        <div class="flex items-center gap-1">
          <.button
            type="button"
            variant="ghost"
            phx-click="go_to_page"
            phx-value-page={@page_info.page_number - 1}
            disabled={@page_info.page_number <= 1}
          >
            Previous
          </.button>
          <.button
            type="button"
            variant="ghost"
            phx-click="go_to_page"
            phx-value-page={@page_info.page_number + 1}
            disabled={@page_info.page_number >= @page_info.total_pages}
          >
            Next
          </.button>
        </div>
      </div>
    </Layouts.pharmacy_shell>
    """
  end
end
