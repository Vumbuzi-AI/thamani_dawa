defmodule ThamaniDawaWeb.DistributorDashboardLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.DistributorOrders
  alias ThamaniDawa.DistributorShipments
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites

  @near_expiry_days 90

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    products = Products.list_products(organization_id)
    sites = Sites.list_sites(organization_id)

    warehouse_ids =
      sites |> Enum.filter(&(&1.site_type == :warehouse and &1.is_active)) |> Enum.map(& &1.id)

    batches =
      organization_id
      |> Batches.list_batches()
      |> Enum.filter(&(&1.site_id in warehouse_ids))

    orders = DistributorOrders.list_orders(organization_id)
    shipments = DistributorShipments.list_shipments(organization_id)
    today = Date.utc_today()
    products_by_id = Map.new(products, &{&1.id, &1})

    available_batches =
      Enum.filter(batches, fn batch ->
        batch.remaining_quantity > 0 and not is_nil(batch.approver_id) and
          Date.compare(batch.expiry_date, today) == :gt
      end)

    near_expiry =
      available_batches
      |> Enum.filter(&(Date.diff(&1.expiry_date, today) in 0..@near_expiry_days))
      |> Enum.sort_by(& &1.expiry_date, Date)
      |> Enum.map(&{&1, Map.get(products_by_id, &1.product_id)})

    product_stock =
      available_batches
      |> Enum.group_by(& &1.product_id)
      |> Enum.map(fn {product_id, product_batches} ->
        {Map.get(products_by_id, product_id),
         Enum.sum(Enum.map(product_batches, & &1.remaining_quantity))}
      end)
      |> Enum.filter(fn {product, _units} -> not is_nil(product) end)

    below_reorder =
      Enum.count(products, fn product ->
        product.reorder_level &&
          Enum.sum(
            for {stocked_product, units} <- product_stock,
                stocked_product.id == product.id,
                do: units
          ) <= product.reorder_level
      end)

    top_products =
      product_stock
      |> Enum.sort_by(fn {_product, units} -> units end, :desc)
      |> Enum.take(5)

    top_product_units =
      top_products
      |> Enum.map(fn {_product, units} -> units end)
      |> Enum.max(fn -> 0 end)

    {:ok,
     socket
     |> assign(:product_count, length(products))
     |> assign(
       :products_in_stock_count,
       available_batches |> Enum.map(& &1.product_id) |> Enum.uniq() |> length()
     )
     |> assign(:available_batch_count, length(available_batches))
     |> assign(
       :warehouse_count,
       sites |> Enum.count(&(&1.site_type == :warehouse and &1.is_active))
     )
     |> assign(
       :orders_awaiting_fulfilment_count,
       Enum.count(orders, &(&1.status in [:pending, :allocated]))
     )
     |> assign(:ready_for_dispatch_count, Enum.count(shipments, &(&1.status == "allocated")))
     |> assign(:near_expiry_all, near_expiry)
     |> assign(:near_expiry_days, @near_expiry_days)
     |> assign(:below_reorder_count, below_reorder)
     |> assign(:top_products, top_products)
     |> assign(:top_product_units, top_product_units)
     |> assign(:pipeline_total, length(orders))
     |> assign(:pipeline_stages, [
       {"Pending", "bg-amber-700", Enum.count(orders, &(&1.status == :pending))},
       {"Allocated", "bg-thamani-forest", Enum.count(orders, &(&1.status == :allocated))},
       {"Dispatched", "bg-emerald-600", Enum.count(orders, &(&1.status == :dispatched))},
       {"Cancelled", "bg-red-600", Enum.count(orders, &(&1.status == :cancelled))}
     ])}
  end

  defp product_name(nil), do: "Unknown product"
  defp product_name(product), do: product.generic_name || product.brand_name || "Unnamed product"
  defp unit_label("H87"), do: "piece(s)"
  defp unit_label("U2"), do: "tablet(s)"
  defp unit_label("C62"), do: "unit(s)"
  defp unit_label(nil), do: "unit(s)"
  defp unit_label(unit), do: if(String.ends_with?(unit, "(s)"), do: unit, else: "#{unit}(s)")

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor"}
    >
      <.header icon="hero-squares-2x2">
        Distributor dashboard
        <:subtitle>
          Inventory health, order flow and dispatch readiness across your organization.
        </:subtitle>
        <:actions>
          <div class="flex flex-wrap items-center gap-3">
            <.button
              id="distributor-receive-stock"
              variant="primary"
              navigate={~p"/distributor/receiving/new"}
            >
              <.icon name="hero-plus" class="size-4" /> Receive stock
            </.button>
            <.button
              id="distributor-new-order"
              variant="ghost"
              navigate={~p"/distributor/orders/new"}
            >
              <.icon name="hero-plus" class="size-4" /> New order
            </.button>
          </div>
        </:actions>
      </.header>

      <div class="dashboard-stat-grid mt-4">
        <.stat_tile
          icon="hero-cube-transparent"
          label="Products in stock"
          value={@products_in_stock_count}
          sublabel="Distinct products with usable stock"
        />
        <.stat_tile
          icon="hero-tag"
          label="Catalog products"
          value={@product_count}
          sublabel="Registered GTINs"
        />
        <.stat_tile
          icon="hero-archive-box"
          label="Active batches"
          value={@available_batch_count}
          sublabel="Usable, unexpired batches with stock"
        />
        <.stat_tile
          icon="hero-map-pin"
          label="Warehouses"
          value={@warehouse_count}
          sublabel="Active distributor warehouse locations"
        />
        <.stat_tile
          icon="hero-exclamation-triangle"
          label="Near-expiry batches"
          value={length(@near_expiry_all)}
          sublabel="Within the current 90-day review window"
        />
        <.stat_tile
          icon="hero-arrow-down-circle"
          label="Below reorder"
          value={@below_reorder_count}
          sublabel="Products needing replenishment"
        />
        <.stat_tile
          icon="hero-clipboard-document-list"
          label="Orders awaiting fulfilment"
          value={@orders_awaiting_fulfilment_count}
          sublabel="Pending or allocated orders"
        />
        <.stat_tile
          icon="hero-truck"
          label="Ready for dispatch"
          value={@ready_for_dispatch_count}
          sublabel="Prepared shipments awaiting dispatch"
        />
      </div>

      <div class="dashboard-chart-grid mt-6">
        <section class="dashboard-chart-card">
          <div class="flex items-start justify-between gap-4">
            <div>
              <h2 class="dashboard-chart-title">Stock by product</h2>
              <p class="dashboard-chart-subtitle">Top products by current units on hand</p>
            </div>
            <span class="dashboard-stat-tile-icon"><.icon name="hero-chart-bar" class="size-4" /></span>
          </div>
          <div class="mt-5 space-y-4">
            <div
              :for={{product, units} <- @top_products}
              class="grid grid-cols-[minmax(7rem,1fr)_minmax(4rem,2fr)_auto] items-center gap-3 text-sm"
            >
              <span class="truncate">{product_name(product)}</span>
              <span class="h-2.5 overflow-hidden rounded-full bg-thamani-stone">
                <span
                  class="block h-full rounded-full bg-thamani-forest"
                  style={"width: #{if(@top_product_units > 0, do: round(units / @top_product_units * 100), else: 0)}%"}
                ></span>
              </span>
              <span class="whitespace-nowrap text-right text-xs font-semibold text-thamani-forest">{units} {unit_label(
                product.uom
              )}</span>
            </div>
            <p :if={@top_products == []} class="py-6 text-center text-sm text-thamani-pewter">
              No stock on hand yet.
            </p>
          </div>
        </section>

        <section class="dashboard-chart-card">
          <div class="flex items-start justify-between gap-4">
            <div>
              <h2 class="dashboard-chart-title">Order pipeline</h2>
              <p class="dashboard-chart-subtitle">Orders by their current fulfillment stage</p>
            </div>
            <span class="dashboard-stat-tile-icon"><.icon name="hero-chart-pie" class="size-4" /></span>
          </div>
          <div class="mt-5 space-y-4">
            <div
              :for={{label, color, count} <- @pipeline_stages}
              class="grid grid-cols-[5.5rem_minmax(0,1fr)_1rem] items-center gap-3 text-sm"
            >
              <span>{label}</span>
              <span class="h-2.5 overflow-hidden rounded-full bg-thamani-stone">
                <span
                  class={["block h-full rounded-full", color]}
                  style={"width: #{if(count > 0, do: max(round(count / max(@pipeline_total, 1) * 100), 8), else: 0)}%"}
                ></span>
              </span>
              <span class="text-right font-semibold text-thamani-forest">{count}</span>
            </div>
          </div>
        </section>
      </div>
    </Layouts.distributor_shell>
    """
  end
end
