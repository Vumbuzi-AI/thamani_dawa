defmodule ThamaniDawaWeb.DistributorDashboardLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Distributor.{Billing, Reports, SerialUsage}
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawaWeb.SiteScoping

  @near_expiry_days 90

  def mount(params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    site_id = SiteScoping.default_site_id(socket.assigns.current_scope)
    products = Products.list_products(organization_id)
    sites = Sites.list_sites(organization_id)

    warehouse_ids =
      if site_id do
        [site_id]
      else
        sites |> Enum.filter(&(Site.distribution?(&1) and &1.is_active)) |> Enum.map(& &1.id)
      end

    batches =
      organization_id
      |> Batches.list_batches()
      |> Enum.filter(&(&1.site_id in warehouse_ids))

    analytics = Reports.shipment_analytics(organization_id, site_id)
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
    organization_id = socket.assigns.current_scope.organization_id
    site_id = SiteScoping.default_site_id(socket.assigns.current_scope)
    analytics = Reports.shipment_analytics(organization_id, site_id)
    {:noreply, socket |> assign(:analytics, analytics) |> assign_pipeline(analytics)}
  end

  defp assign_pipeline(socket, %{status_counts: counts}) do
    socket
    |> assign(:pipeline_total, counts |> Map.values() |> Enum.sum())
    |> assign(:pipeline_stages, [
      %{
        status: "draft",
        label: "Draft",
        caption: "Being packed",
        tone: "neutral",
        count: counts["draft"] || 0
      },
      %{
        status: "submitted",
        label: "Submitted",
        caption: "Awaiting review",
        tone: "warning",
        count: counts["submitted"] || 0
      },
      %{
        status: "approved",
        label: "Approved",
        caption: "SSCCs issued",
        tone: "success",
        count: counts["approved"] || 0
      },
      %{
        status: "rejected",
        label: "Rejected",
        caption: "Returned for changes",
        tone: "danger",
        count: counts["rejected"] || 0
      }
    ])
  end

  defp product_tour_steps do
    [
      %{
        selector: ~s([data-tour-target="/distributor"]),
        title: "See what needs attention",
        description:
          "Start here for shipments awaiting review, serialisation activity, and warehouse stock health."
      },
      %{
        selector: ~s([data-tour-target="/distributor/shipments"]),
        title: "Approve ready shipments",
        description:
          "Review submitted shipments, return incomplete ones, and track packing drafts."
      },
      %{
        selector: ~s([data-tour-target="/distributor/mobile-users"]),
        title: "Set up mobile packers",
        description: "Add the people who scan, pack, and submit shipments from the mobile app."
      },
      %{
        selector: ~s([data-tour-target="/distributor/receiving"]),
        title: "Receive deliveries",
        description:
          "Record supplier deliveries before their stock becomes available in the warehouse."
      },
      %{
        selector: ~s([data-tour-target="/distributor/products"]),
        title: "Review inventory",
        description:
          "Register the GTINs you distribute, and see the batches, holds, and short-dated stock on hand."
      },
      %{
        selector: ~s([data-tour-target="/org/sites"]),
        title: "Manage warehouse locations",
        description: "Set up the sites where stock is received, stored, and dispatched."
      },
      %{
        selector: ~s([data-tour-target="/distributor/epcis"]),
        title: "Monitor TNT reporting",
        description:
          "Check whether reportable events reached PPB and resolve anything that needs resubmission."
      },
      %{
        selector: ~s([data-tour-target="/distributor/billing"]),
        title: "Keep shipments funded",
        description:
          "Buy prepay bundles or settle your flex cycle to keep serialisation available."
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

  defp plan_caption(nil), do: "Choose a serialisation plan"
  defp plan_caption(%SerialUsage{type: "prepay"}), do: "Prepay bundle"
  defp plan_caption(%SerialUsage{}), do: "Flex plan"

  defp shipment_tone("submitted"), do: "warning"
  defp shipment_tone("approved"), do: "success"
  defp shipment_tone("rejected"), do: "danger"
  defp shipment_tone(_status), do: "neutral"

  defp shipment_label(nil), do: "Unknown"
  defp shipment_label(status), do: status |> to_string() |> Phoenix.Naming.humanize()

  defp phrase(count, singular, plural),
    do: "#{number(count || 0)} #{if count == 1, do: singular, else: plural}"

  def render(assigns) do
    assigns =
      assign(
        assigns,
        :pipeline_max,
        assigns.pipeline_stages |> Enum.map(fn stage -> stage.count end) |> Enum.max(fn -> 0 end)
      )

    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor"}
      crumb="Dashboard"
    >
      <:tools>
        <.td_button
          id="distributor-new-shipment"
          variant="primary"
          label="New order"
          glyph="plus"
          navigate={~p"/distributor/orders/new"}
        />
      </:tools>

      <.td_dashboard
        id="distributor-dashboard"
        title="Distributor dashboard"
        subtitle="Shipments awaiting review, SSCC issuance, and inventory health across your organization."
      >
        <:actions>
          <.td_button
            id="distributor-receive-stock"
            label="Receive stock"
            glyph="tray-arrow-down"
            navigate={~p"/distributor/receiving/new"}
          />
        </:actions>
        <:notice>
          <div :if={!@plan_selected?} id="distributor-plan-required" class="td-notice">
            <div>
              <p class="td-notice-title">Choose a serialisation plan</p>
              <p class="td-note">
                Shipments can't be created or approved until you pick a prepay bundle or flex pay-as-you-go.
              </p>
            </div>
            <.td_button
              id="distributor-choose-plan"
              variant="primary"
              label="Choose a plan"
              navigate={~p"/distributor/billing/options"}
            />
          </div>
        </:notice>
        <:strip id="distributor-attention">
          <.td_glance_cell
            id="stat-shipments-submitted"
            navigate={~p"/distributor/orders?#{%{status: "submitted"}}"}
            tone="warning"
            value={"#{number(@analytics.status_counts["submitted"] || 0)} awaiting review"}
            caption="Shipments to approve or reject"
          >
            <:icon><.td_icon name="hourglass" class="size-[18px]" /></:icon>
          </.td_glance_cell>
          <.td_glance_cell
            id="stat-shipments-draft"
            navigate={~p"/distributor/orders?#{%{status: "draft"}}"}
            tone="neutral"
            value={phrase(@analytics.status_counts["draft"], "draft", "drafts")}
            caption="Being packed on the mobile app"
          >
            <:icon><.td_icon name="package" class="size-[18px]" /></:icon>
          </.td_glance_cell>
          <.td_glance_cell
            id="stat-near-expiry-link"
            navigate={~p"/distributor/products?#{%{view: "batches", expiry: "near"}}"}
            tone="expiry"
            value={phrase(length(@near_expiry_all), "near-expiry batch", "near-expiry batches")}
            caption={"Expiring within #{@near_expiry_days} days"}
          >
            <:icon><.td_icon name="calendar-x" class="size-[18px]" /></:icon>
          </.td_glance_cell>
          <.td_glance_cell
            id="stat-below-reorder"
            navigate={~p"/distributor/products"}
            tone="danger"
            value={"#{number(@below_reorder_count)} below reorder"}
            caption="Products to restock"
          >
            <:icon><.td_icon name="trend-down" class="size-[18px]" /></:icon>
          </.td_glance_cell>
        </:strip>
        <:strip id="distributor-overview">
          <.td_glance_cell
            id="stat-shipments-approved-month"
            tone="success"
            value={"#{number(@analytics.approved_this_month)} approved this month"}
            caption={"#{number(@analytics.ssccs_issued)} SSCCs issued"}
          >
            <:icon><.td_icon name="check-circle" class="size-[18px]" /></:icon>
          </.td_glance_cell>
          <.td_glance_cell
            id="stat-products-in-stock"
            navigate={~p"/distributor/products"}
            tone="neutral"
            value={phrase(@products_in_stock_count, "product in stock", "products in stock")}
            caption="Distinct products with usable stock"
          >
            <:icon><.td_icon name="link" class="size-[18px]" /></:icon>
          </.td_glance_cell>
          <.td_glance_cell
            id="stat-active-batches"
            navigate={~p"/distributor/products?#{%{view: "batches"}}"}
            tone="neutral"
            value={phrase(@available_batch_count, "active batch", "active batches")}
            caption="Usable, unexpired batches with stock"
          >
            <:icon><.td_icon name="stack" class="size-[18px]" /></:icon>
          </.td_glance_cell>
          <.td_glance_cell
            id="stat-ssccs-issued"
            navigate={~p"/distributor/billing"}
            tone="info"
            value={allowance_label(@usage)}
            caption={plan_caption(@usage)}
          >
            <:icon><.td_icon name="barcode" class="size-[18px]" /></:icon>
          </.td_glance_cell>
        </:strip>

        <.td_dash_row>
          <.td_dash_card
            id="distributor-recent-shipments"
            title="Recent shipments"
            subtitle="Latest activity across all statuses"
          >
            <:actions>
              <.td_button label="View all" navigate={~p"/distributor/shipments"} />
            </:actions>
            <table :if={@analytics.recent_shipments != []} class="td-rows is-tight">
              <thead>
                <tr>
                  <th>Order</th>
                  <th>Status</th>
                  <th>To</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={shipment <- @analytics.recent_shipments}
                  id={"recent-shipment-#{shipment.id}"}
                  class="is-link"
                  phx-click={
                    JS.navigate(
                      ~p"/distributor/shipments/#{shipment.id}?#{%{return_to: "/distributor"}}"
                    )
                  }
                >
                  <td class="td-mono">{shipment.order_number || shipment.reference}</td>
                  <td>
                    <.td_badge
                      tone={shipment_tone(shipment.status)}
                      label={shipment_label(shipment.status)}
                    />
                  </td>
                  <td>{shipment.destination_company}</td>
                </tr>
              </tbody>
            </table>
            <p :if={@analytics.recent_shipments == []} class="td-dash-empty">No shipments yet.</p>
          </.td_dash_card>

          <.td_dash_card
            id="distributor-shipment-pipeline"
            title="Shipment pipeline"
            subtitle="Shipments by their current lifecycle stage"
            width={320}
          >
            <.td_tick_row
              :for={stage <- @pipeline_stages}
              label={stage.label}
              caption={stage.caption}
              count={stage.count}
              max={@pipeline_max}
              tone={stage.tone}
              navigate={~p"/distributor/shipments?#{%{status: stage.status}}"}
            />
          </.td_dash_card>

          <.td_dash_card
            id="distributor-stock-by-product"
            title="Stock by product"
            subtitle="Top products by current units on hand"
            width={360}
          >
            <table :if={@top_products != []} class="td-rows is-tight">
              <thead>
                <tr>
                  <th>Product</th>
                  <th class="is-num">Units</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={{product, units} <- @top_products}
                  class="is-link"
                  phx-click={JS.navigate(~p"/distributor/products/#{product.id}")}
                >
                  <td>{product_name(product)}</td>
                  <td class="is-num">
                    <.td_ticks count={units} max={@top_product_units} tone="neutral" />{number(units)}
                  </td>
                </tr>
              </tbody>
            </table>
            <p :if={@top_products == []} class="td-dash-empty">No stock on hand yet.</p>
          </.td_dash_card>
        </.td_dash_row>
      </.td_dashboard>

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
