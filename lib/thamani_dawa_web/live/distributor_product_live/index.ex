defmodule ThamaniDawaWeb.DistributorProductLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Products
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawa.Suppliers
  alias ThamaniDawaWeb.DistributorPagination
  alias ThamaniDawaWeb.SiteScoping

  @inventory_zones [:receiving, :storage, :quarantine]

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    sites = Sites.list_sites(organization_id)

    warehouse_ids =
      sites |> Enum.filter(&(Site.distribution?(&1) and &1.is_active)) |> Enum.map(& &1.id)

    {:ok,
     socket
     |> assign(:view, "products")
     |> assign(:search, "")
     |> assign(:page_number, 1)
     |> assign(:expiry_filter, "all")
     |> assign(:hold_filter, "all")
     |> assign(:product_count, 0)
     |> assign(:batch_count, 0)
     |> assign(:today, Date.utc_today())
     |> assign(:products_by_id, Map.new(Products.list_products(organization_id), &{&1.id, &1}))
     |> assign(:sites_by_id, Map.new(sites, &{&1.id, &1}))
     |> assign(:warehouse_ids, warehouse_ids)
     |> assign(
       :suppliers_by_id,
       Map.new(Suppliers.list_suppliers(organization_id), &{&1.id, &1})
     )}
  end

  def handle_params(params, _url, socket) do
    view = if params["view"] == "batches", do: "batches", else: "products"

    form =
      if socket.assigns.live_action == :new do
        to_form(Product.changeset(%Product{}, %{"uom" => "C62"}), as: :product)
      else
        nil
      end

    {:noreply,
     socket
     |> assign(:view, view)
     |> assign(:search, Map.get(params, "search", ""))
     |> assign(:page_number, DistributorPagination.page_number(params))
     |> assign(:expiry_filter, expiry_param(params))
     |> assign(:hold_filter, hold_param(params))
     |> assign(:today, Date.utc_today())
     |> assign(:form, form)
     |> reload_view()}
  end

  def handle_event("validate", %{"product" => attrs}, socket) do
    changeset =
      Map.put(Product.changeset(%Product{}, stock_unit_attrs(attrs)), :action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :product))}
  end

  def handle_event("save", %{"product" => attrs}, socket) do
    case Products.create_product(
           socket.assigns.current_scope.organization_id,
           stock_unit_attrs(attrs)
         ) do
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
    {:noreply, push_patch(socket, to: inventory_path(socket, %{view: view}))}
  end

  def handle_event("set_filter", %{"field" => "expiry", "value" => value}, socket) do
    expiry = if value == "", do: "all", else: value
    {:noreply, push_patch(socket, to: inventory_path(socket, %{view: "batches", expiry: expiry}))}
  end

  def handle_event("set_filter", %{"field" => "hold", "value" => value}, socket) do
    hold = if value == "", do: "all", else: value
    {:noreply, push_patch(socket, to: inventory_path(socket, %{view: "batches", hold: hold}))}
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> assign(:page_number, 1) |> reload_view()}
  end

  defp stock_unit_attrs(attrs) do
    if attrs["uom"] in [nil, ""], do: Map.put(attrs, "uom", "C62"), else: attrs
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
        stock_site_ids(socket)
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
    |> assign(:product_count, length(products))
    |> assign(:batch_count, inventory_batch_count(socket))
    |> assign(:page_info, page_info)
    |> stream(:products, page_info.entries, reset: true)
  end

  defp reload_batches(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    search = String.downcase(String.trim(socket.assigns.search))

    site_ids = stock_site_ids(socket)

    inventory =
      organization_id
      |> Batches.list_batches()
      |> Enum.filter(&in_inventory?(&1, site_ids))

    batches =
      inventory
      |> Enum.filter(fn batch ->
        product = socket.assigns.products_by_id[batch.product_id]

        search == "" or
          Enum.any?(
            [
              product && product.generic_name,
              product && product.brand_name,
              batch.gtin,
              batch.batch_no
            ],
            &(is_binary(&1) and String.contains?(String.downcase(&1), search))
          )
      end)
      |> filter_hold(socket.assigns.hold_filter)
      |> filter_expiry(socket.assigns.expiry_filter, socket.assigns.today)
      |> Enum.sort_by(& &1.expiry_date, Date)

    page_info = DistributorPagination.page(batches, socket.assigns.page_number)

    socket
    |> assign(:product_count, map_size(socket.assigns.products_by_id))
    |> assign(:batch_count, length(inventory))
    |> assign(:page_info, page_info)
    |> stream(:batches, page_info.entries, reset: true)
  end

  defp pagination_path(view, search, expiry, hold) do
    inventory_query(view, search, expiry, hold)
  end

  defp inventory_path(socket, overrides) do
    inventory_query(
      Map.get(overrides, :view, socket.assigns.view),
      Map.get(overrides, :search, socket.assigns.search),
      Map.get(overrides, :expiry, socket.assigns.expiry_filter),
      Map.get(overrides, :hold, socket.assigns.hold_filter)
    )
  end

  defp inventory_query(view, search, expiry, hold) do
    params =
      %{}
      |> maybe_put("view", "batches", view == "batches")
      |> maybe_put("search", search, search not in [nil, ""])
      |> maybe_put("expiry", expiry, view == "batches" and expiry not in [nil, "all"])
      |> maybe_put("hold", hold, view == "batches" and hold not in [nil, "all"])

    ~p"/distributor/products?#{params}"
  end

  defp maybe_put(params, _key, _value, false), do: params
  defp maybe_put(params, key, value, true), do: Map.put(params, key, value)

  defp stock_site_ids(socket) do
    case SiteScoping.default_site_id(socket.assigns.current_scope) do
      nil -> socket.assigns.warehouse_ids
      site_id -> [site_id]
    end
  end

  defp inventory_batch_count(socket) do
    site_ids = stock_site_ids(socket)

    socket.assigns.current_scope.organization_id
    |> Batches.list_batches()
    |> Enum.count(&in_inventory?(&1, site_ids))
  end

  defp in_inventory?(batch, site_ids) do
    batch.remaining_quantity > 0 and
      batch.zone in @inventory_zones and
      batch.site_id in site_ids
  end

  defp expiry_param(params) do
    case Map.get(params, "expiry", "all") do
      "critical" -> "critical"
      "expired" -> "expired"
      "near" -> "near"
      window when window in ["warning", "watch"] -> "near"
      _ -> "all"
    end
  end

  defp hold_param(params) do
    if Map.get(params, "hold") == "quarantine", do: "quarantine", else: "all"
  end

  defp filter_hold(batches, "quarantine") do
    Enum.filter(batches, &(&1.zone == :quarantine or &1.status == :quarantined))
  end

  defp filter_hold(batches, _hold), do: batches

  defp filter_expiry(batches, "all", _today), do: batches

  defp filter_expiry(batches, "near", today) do
    Enum.filter(batches, &(expiry_tier(&1, today) in [:critical, :warning, :watch]))
  end

  defp filter_expiry(batches, tier, today) do
    Enum.filter(batches, &(expiry_tier(&1, today) == String.to_existing_atom(tier)))
  end

  defp expiry_tier(%{expiry_date: nil}, _today), do: nil

  defp expiry_tier(%{status: :active, expiry_date: expiry}, today) do
    days = Date.diff(expiry, today)

    cond do
      days < 0 -> :expired
      days <= 30 -> :critical
      days <= 60 -> :warning
      days <= 90 -> :watch
      true -> nil
    end
  end

  defp expiry_tier(%{expiry_date: expiry}, today) do
    if Date.diff(expiry, today) < 0, do: :expired, else: nil
  end

  defp expiry_badge_label(:critical), do: "30 days or less"
  defp expiry_badge_label(:warning), do: "31–60 days"
  defp expiry_badge_label(:watch), do: "61–90 days"
  defp expiry_badge_label(:expired), do: "Expired"

  defp expiry_badge_class(:critical), do: "bg-red-100 text-red-800"
  defp expiry_badge_class(:warning), do: "bg-amber-100 text-amber-800"
  defp expiry_badge_class(:watch), do: "bg-yellow-50 text-yellow-800"
  defp expiry_badge_class(:expired), do: "bg-red-100 text-red-800"

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
  defp date_or_dash(date), do: ThamaniDawaWeb.TimeFormat.date(date)

  defp quantity_with_unit(quantity, _product), do: Products.format_unit_count(quantity)

  defp batch_status_label(:inactive), do: "Lost"
  defp batch_status_label(:non_sellable_other), do: "Exported"
  defp batch_status_label(status), do: Phoenix.Naming.humanize(status)

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/products"}
    >
      <:search>
        <form phx-change="search" id="distributor-product-search">
          <.td_search
            name="search"
            value={@search}
            placeholder={
              if @view == "products",
                do: "Search by product, GTIN, or category",
                else: "Search by product, GTIN, or batch number"
            }
            shortcut="⌘K"
            phx-debounce="200"
          />
        </form>
      </:search>
      <.td_list_page
        title="Inventory"
        subtitle={
          if @view == "products",
            do: "The products this warehouse distributes, and how much of each is on hand.",
            else: "Batches still in this warehouse."
        }
      >
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
        <:tabs>
          <button
            id="distributor-products-tab"
            type="button"
            class={["td-tab", @view == "products" && "is-active"]}
            phx-click="set_view"
            phx-value-view="products"
            aria-current={@view == "products" && "page"}
          >
            Products <.td_count value={@product_count} />
          </button>
          <button
            id="distributor-batches-tab"
            type="button"
            class={["td-tab", @view == "batches" && "is-active"]}
            phx-click="set_view"
            phx-value-view="batches"
            aria-current={@view == "batches" && "page"}
          >
            Batches <.td_count value={@batch_count} />
          </button>
        </:tabs>
        <:filters :if={@view == "batches"}>
          <.td_filter_menu
            :if={@view == "batches"}
            id="distributor-batches"
            field="hold"
            label="Stock"
            value={if @hold_filter == "all", do: "", else: @hold_filter}
            options={[{"", "All stock"}, {"quarantine", "Quarantine"}]}
          />
          <.td_filter_menu
            :if={@view == "batches"}
            id="distributor-batches"
            field="expiry"
            label="Expiry"
            value={if @expiry_filter == "all", do: "", else: @expiry_filter}
            options={[
              {"", "Any date"},
              {"critical", "Within 30 days"},
              {"near", "Within 90 days"},
              {"expired", "Expired"}
            ]}
          />
        </:filters>

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
              <input type="hidden" name="product[uom]" value="C62" />
              <.input field={@form[:generic_name]} label="Generic name" />
              <.input field={@form[:brand_name]} label="Brand name" />
              <.input field={@form[:gtin]} label="GTIN" required />
              <.input
                field={@form[:net_content_quantity]}
                type="number"
                label="Each pack contains (optional)"
                placeholder="e.g. 20"
                min="1"
              />
              <.input
                field={@form[:net_content_uom]}
                type="select"
                label="What's inside"
                prompt="Tablets, capsules, ml"
                options={[
                  {"Tablets", "U2"},
                  {"Capsules", "AV"},
                  {"Millilitres", "MLT"},
                  {"Pieces", "H87"}
                ]}
              />
              <.input field={@form[:category]} label="Category" />
              <.input field={@form[:manufacturer]} label="Manufacturer" />
              <.input field={@form[:price]} type="number" label="Price (KSh)" min="0" required />
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
            <:col :let={{_id, row}} label="Strength" mobile="hidden" tablet="hidden">
              {row.product.strength || "—"}
            </:col>
            <:col :let={{_id, row}} label="Price">{money(row.product.price)}</:col>
            <:col :let={{_id, row}} label="Batches">{row.batch_count}</:col>
            <:col :let={{_id, row}} label="Status">
              <.status_badge status={if row.product.is_active, do: :active, else: :inactive} />
            </:col>
            <:col :let={{_id, row}} label="GTIN">
              <span class="font-mono">{row.product.gtin}</span>
            </:col>
            <:col :let={{_id, row}} label="Unit">{Products.unit_label(row.product.uom)}</:col>
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
            <:col
              :let={{_id, batch}}
              :if={is_nil(SiteScoping.default_site_id(@current_scope))}
              label="Warehouse"
            >
              {site_name(@sites_by_id[batch.site_id])}
            </:col>
            <:col :let={{_id, batch}} label="Expiry">
              <span class="text-thamani-pewter">{date_or_dash(batch.expiry_date)}</span>
              <span
                :if={tier = expiry_tier(batch, @today)}
                class={[
                  "ml-1.5 rounded-full px-2 py-0.5 text-xs font-semibold",
                  expiry_badge_class(tier)
                ]}
              >
                {expiry_badge_label(tier)}
              </span>
            </:col>
            <:col :let={{_id, batch}} label="Qty">
              {quantity_with_unit(batch.remaining_quantity, @products_by_id[batch.product_id])}
            </:col>
            <:col :let={{_id, batch}} label="Status">
              <.status_badge status={batch.status} label={batch_status_label(batch.status)} />
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
        <.pagination
          page={@page_info}
          path={pagination_path(@view, @search, @expiry_filter, @hold_filter)}
        />
      </.td_list_page>
    </Layouts.distributor_shell>
    """
  end
end
