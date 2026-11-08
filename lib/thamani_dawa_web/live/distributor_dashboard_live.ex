defmodule ThamaniDawaWeb.DistributorDashboardLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Distributor.{Billing, Reports, SerialUsage}
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites

  @near_expiry_days 90

  def mount(params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    products = Products.list_products(organization_id)
    sites = Sites.list_sites(organization_id)

    warehouse_ids =
      sites |> Enum.filter(&(&1.site_type == :warehouse and &1.is_active)) |> Enum.map(& &1.id)

    batches =
      organization_id
      |> Batches.list_batches()
      |> Enum.filter(&(&1.site_id in warehouse_ids))

    analytics = Reports.shipment_analytics(organization_id)
    usage = Billing.active_usage(organization_id)
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

    if connected?(socket), do: Distributor.subscribe(organization_id)

    {:ok,
     socket
     |> assign(:auto_start_tour?, params["tour"] == "1")
     |> assign(:analytics, analytics)
     |> assign(:plan_selected?, Billing.plan_selected?(organization_id))
     |> assign(:usage, usage)
     |> assign(
       :products_in_stock_count,
       available_batches |> Enum.map(& &1.product_id) |> Enum.uniq() |> length()
     )
     |> assign(:available_batch_count, length(available_batches))
     |> assign(:near_expiry_all, near_expiry)
     |> assign(:near_expiry_days, @near_expiry_days)
     |> assign(:below_reorder_count, below_reorder)
     |> assign(:top_products, top_products)
     |> assign(:top_product_units, top_product_units)
     |> assign_pipeline(analytics)}
  end

  def handle_info({:distributor_shipment, _event, _shipment_id}, socket) do
    analytics = Reports.shipment_analytics(socket.assigns.current_scope.organization_id)
    {:noreply, socket |> assign(:analytics, analytics) |> assign_pipeline(analytics)}
  end

  defp assign_pipeline(socket, %{status_counts: counts}) do
    socket
    |> assign(:pipeline_total, counts |> Map.values() |> Enum.sum())
    |> assign(:pipeline_stages, [
      {"Draft", "bg-slate-400", counts["draft"]},
      {"Submitted", "bg-amber-700", counts["submitted"]},
      {"Approved", "bg-thamani-forest", counts["approved"]},
      {"Rejected", "bg-red-600", counts["rejected"]}
    ])
  end

  defp product_tour_steps do
    [
      %{
        selector: ~s([data-tour-target="/distributor"]),
        title: "Start with your dashboard",
        description:
          "See shipments awaiting review, SSCC issuance, and inventory health at a glance."
      },
      %{
        selector: ~s([data-tour-target="/distributor/shipments"]),
        title: "Review shipments",
        description: "Approve or reject submitted shipments and track drafts being packed."
      },
      %{
        selector: ~s([data-tour-target="/distributor/mobile-users"]),
        title: "Manage mobile users",
        description: "Add the packers who scan and submit shipments from the mobile app."
      },
      %{
        selector: ~s([data-tour-target="/distributor/receiving"]),
        title: "Receive incoming stock",
        description: "Post deliveries from suppliers into your warehouse inventory."
      },
      %{
        selector: ~s([data-tour-target="/distributor/products"]),
        title: "Maintain your catalog",
        description: "Register the GTINs you distribute, with reorder levels for each product."
      },
      %{
        selector: ~s([data-tour-target="/distributor/suppliers"]),
        title: "Track your suppliers",
        description: "Keep the suppliers you receive stock from up to date."
      },
      %{
        selector: ~s([data-tour-target="/distributor/warehouses"]),
        title: "Set up your warehouses",
        description: "Register the sites stock is received into and shipped from."
      },
      %{
        selector: ~s([data-tour-target="/distributor/customers"]),
        title: "Manage your customers",
        description: "Keep the GLNs and details of who you ship to up to date."
      },
      %{
        selector: ~s([data-tour-target="/distributor/billing"]),
        title: "Keep serialisation funded",
        description: "Buy prepay bundles or settle your flex cycle to keep shipments unlocked."
      }
    ]
  end

  defp allowance_label(nil), do: "No active plan"

  defp allowance_label(%SerialUsage{type: "prepay"} = usage),
    do: "#{SerialUsage.serials_left(usage)} serials left"

  defp allowance_label(%SerialUsage{} = usage),
    do: "#{SerialUsage.generated(usage)} generated this cycle"

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
          Shipments awaiting review, SSCC issuance, and inventory health across your organization.
        </:subtitle>
        <:actions>
          <div class="flex flex-wrap items-center gap-3">
            <.button
              id="distributor-new-shipment"
              variant="primary"
              navigate={~p"/distributor/shipments/new"}
            >
              <.icon name="hero-plus" class="size-4" /> New shipment
            </.button>
            <.button
              id="distributor-receive-stock"
              variant="ghost"
              navigate={~p"/distributor/receiving/new"}
            >
              <.icon name="hero-arrow-down-tray" class="size-4" /> Receive stock
            </.button>
          </div>
        </:actions>
      </.header>

      <div
        :if={!@plan_selected?}
        id="distributor-plan-required"
        class="mt-4 flex flex-col gap-3 rounded-2xl border border-amber-200 bg-amber-50 p-5 sm:flex-row sm:items-center sm:justify-between"
      >
        <div class="flex items-start gap-3">
          <.icon name="hero-credit-card" class="mt-0.5 size-5 shrink-0 text-amber-700" />
          <div>
            <p class="text-sm font-semibold text-amber-900">Choose a serialisation plan</p>
            <p class="text-sm text-amber-800">
              Shipments can't be created or approved until you pick a prepay bundle or flex pay-as-you-go.
            </p>
          </div>
        </div>
        <.button
          id="distributor-choose-plan"
          variant="primary"
          navigate={~p"/distributor/billing/options"}
        >
          Choose a plan
        </.button>
      </div>

      <p class="dashboard-section-label mt-6">Needs attention</p>
      <div class="dashboard-stat-grid mt-2">
        <.stat_tile
          id="stat-shipments-submitted"
          icon="hero-inbox-arrow-down"
          label="Awaiting review"
          value={@analytics.status_counts["submitted"]}
          sublabel="Submitted shipments to approve or reject"
        />
        <.stat_tile
          id="stat-shipments-draft"
          icon="hero-pencil-square"
          label="Drafts"
          value={@analytics.status_counts["draft"]}
          sublabel="Being packed on the mobile app"
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
      </div>

      <p class="dashboard-section-label mt-6">Overview</p>
      <div class="dashboard-stat-grid mt-2">
        <.stat_tile
          id="stat-shipments-approved-month"
          icon="hero-check-badge"
          label="Approved this month"
          value={@analytics.approved_this_month}
          sublabel={"#{@analytics.units_shipped} units shipped in total"}
        />
        <.stat_tile
          id="stat-ssccs-issued"
          icon="hero-qr-code"
          label="SSCCs issued"
          value={@analytics.ssccs_issued}
          sublabel={allowance_label(@usage)}
        />
        <.stat_tile
          icon="hero-cube-transparent"
          label="Products in stock"
          value={@products_in_stock_count}
          sublabel="Distinct products with usable stock"
        />
        <.stat_tile
          icon="hero-archive-box"
          label="Active batches"
          value={@available_batch_count}
          sublabel="Usable, unexpired batches with stock"
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
              <h2 class="dashboard-chart-title">Shipment pipeline</h2>
              <p class="dashboard-chart-subtitle">Shipments by their current lifecycle stage</p>
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

      <div class="dashboard-chart-grid mt-6">
        <section class="dashboard-chart-card" id="distributor-recent-shipments">
          <div class="flex items-start justify-between gap-4">
            <div>
              <h2 class="dashboard-chart-title">Recent shipments</h2>
              <p class="dashboard-chart-subtitle">Latest activity across all statuses</p>
            </div>
            <.link
              navigate={~p"/distributor/shipments"}
              class="text-xs font-semibold text-thamani-forest hover:underline"
            >
              View all
            </.link>
          </div>
          <ul class="mt-4 divide-y divide-thamani-stone">
            <li :for={shipment <- @analytics.recent_shipments} class="py-3">
              <.link
                navigate={~p"/distributor/shipments/#{shipment.id}"}
                class="group flex items-center justify-between gap-3 text-sm"
              >
                <div class="min-w-0">
                  <p class="truncate font-medium text-thamani-forest group-hover:underline">
                    {shipment.order_number}
                  </p>
                  <p class="truncate text-xs text-thamani-pewter">
                    {shipment.reference} · {shipment.destination_company}
                  </p>
                </div>
                <.shipment_status_badge status={shipment.status} />
              </.link>
            </li>
            <li
              :if={@analytics.recent_shipments == []}
              class="py-6 text-center text-sm text-thamani-pewter"
            >
              No shipments yet.
            </li>
          </ul>
        </section>

        <section class="dashboard-chart-card" id="distributor-top-shipped">
          <div class="flex items-start justify-between gap-4">
            <div>
              <h2 class="dashboard-chart-title">Top shipped products</h2>
              <p class="dashboard-chart-subtitle">Units in approved shipments</p>
            </div>
            <span class="dashboard-stat-tile-icon"><.icon name="hero-truck" class="size-4" /></span>
          </div>
          <ul class="mt-4 divide-y divide-thamani-stone">
            <li
              :for={product <- @analytics.top_products}
              class="flex items-center justify-between gap-3 py-3 text-sm"
            >
              <div class="min-w-0">
                <p class="truncate font-medium text-thamani-ink">
                  {product.product_name || "Unverified product"}
                </p>
                <p class="font-mono text-xs text-thamani-pewter">{product.gtin}</p>
              </div>
              <span class="whitespace-nowrap font-semibold text-thamani-forest">
                {product.units} units
              </span>
            </li>
            <li
              :if={@analytics.top_products == []}
              class="py-6 text-center text-sm text-thamani-pewter"
            >
              Nothing shipped yet.
            </li>
          </ul>
        </section>
      </div>

      <Layouts.product_tour
        id="distributor-product-tour"
        tour_key={"thamani-distributor-tour-v1-#{@current_scope.user.id}"}
        auto_start={@auto_start_tour?}
        steps={product_tour_steps()}
      />
    </Layouts.distributor_shell>
    """
  end
end
