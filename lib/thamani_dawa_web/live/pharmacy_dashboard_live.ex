defmodule ThamaniDawaWeb.PharmacyDashboardLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Dashboards
  alias ThamaniDawa.Prescriptions
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawa.StockAlerts
  alias ThamaniDawaWeb.SiteScoping

  @near_expiry_days 30

  def mount(params, _session, socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    site_id = scope.current_site_id

    products_by_id = organization_id |> Products.list_products() |> Map.new(&{&1.id, &1})

    active_batches =
      organization_id
      |> Batches.list_batches()
      |> SiteScoping.for_current_site(scope)
      |> Enum.filter(&(not is_nil(&1.approver_id)))

    pending_batches =
      organization_id
      |> Batches.list_pending_batches()
      |> SiteScoping.for_current_site(scope)

    prescriptions =
      organization_id
      |> Prescriptions.list_prescriptions()
      |> SiteScoping.for_current_site(scope)
      |> Enum.filter(&(&1.status in [:pending, :partially_dispensed]))

    {out_of_stock, low_stock} = StockAlerts.stock_alerts(active_batches, products_by_id)

    {:ok,
     socket
     |> assign(:auto_start_tour?, params["tour"] == "1")
     |> assign(:multi_site?, Sites.multi_site?(organization_id))
     |> assign(:products_by_id, products_by_id)
     |> assign(:out_of_stock, out_of_stock)
     |> assign(:low_stock, low_stock)
     |> assign(:near_expiry, StockAlerts.near_expiry(active_batches, @near_expiry_days))
     |> assign(:near_expiry_days, @near_expiry_days)
     |> assign(:pending_batches_count, length(pending_batches))
     |> assign(:pending_prescriptions, prescriptions)
     |> assign(:stats, Dashboards.pharmacy_stats(organization_id, site_id))
     |> assign(:dispensed_today, Dashboards.dispensed_today(organization_id, site_id))
     |> assign(:top_products, Dashboards.top_dispensed_products(organization_id, site_id))}
  end

  defp product_tour_steps(multi_site?) do
    [
      %{
        selector: ~s([data-tour-target="/pharmacy"]),
        title: "See today’s workload",
        description:
          "See today’s pharmacy workload, stock alerts, revenue, and dispensing activity at a glance."
      },
      %{
        selector: ~s([data-tour-target="/pharmacy/quick-sale"]),
        title: "Record an over-the-counter sale",
        description:
          "Dispense non-prescription items and complete a sale directly from the pharmacy."
      },
      %{
        selector: ~s([data-tour-target="/pharmacy/prescriptions"]),
        title: "Manage prescriptions",
        description:
          "Review prescriptions waiting to be dispensed and follow each order through completion."
      },
      %{
        selector: ~s([data-tour-target="/pharmacy/patients"]),
        title: "Find a patient",
        description:
          "Look up patient records and review their prescription and dispensing history."
      },
      %{
        selector: ~s([data-tour-target="/pharmacy/stock"]),
        title: "Check site stock",
        description:
          "Check available medicines, batches, expiry dates, and quantities at your current site."
      },
      %{
        selector: ~s([data-tour-target="/pharmacy/receive-stock"]),
        title: "Receive incoming stock",
        description:
          "Confirm stock dispatched to your site before it becomes available for dispensing."
      },
      %{
        selector: ~s([data-tour-target="/pharmacy/requisitions"]),
        title: "Request stock",
        description: "Ask your organization for stock when your site needs a replenishment."
      },
      %{
        selector: ~s([data-tour-target="/pharmacy/scan"]),
        title: "Scan products and batches",
        description:
          "Use scanning to identify products and batches quickly during day-to-day work."
      },
      %{
        selector: ~s([data-tour-target="/pharmacy/transactions"]),
        title: "Review completed work",
        description: "Find completed sales and dispensing activity for the current pharmacy site."
      }
    ]
    |> Enum.reject(fn step ->
      not multi_site? and step.selector == ~s([data-tour-target="/pharmacy/requisitions"])
    end)
  end

  defp product_name(nil), do: "(unknown product)"
  defp product_name(product), do: product.generic_name || product.brand_name || "(unnamed)"

  defp money(%Decimal{} = amount), do: amount |> Decimal.to_float() |> money()
  defp money(nil), do: "KSh 0"

  defp money(amount) when is_number(amount) do
    grouped =
      amount
      |> round()
      |> Integer.to_string()
      |> String.reverse()
      |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
      |> String.reverse()

    "KSh " <> grouped
  end

  defp phrase(1, one, _many), do: "1 #{one}"
  defp phrase(count, _one, many), do: "#{count} #{many}"

  defp paid_label(true), do: "Paid"
  defp paid_label(_), do: "Unpaid"

  defp patient_label(%{patient_name: name}) when is_binary(name) and name != "", do: name
  defp patient_label(_), do: "Patient"

  defp stock_health_max(out, low, near, pending) do
    max(length(out) + length(low) + length(near) + pending, 1)
  end

  defp top_products_max([]), do: 1
  defp top_products_max(products), do: products |> Enum.map(&elem(&1, 1)) |> Enum.max() |> max(1)

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/pharmacy"
      crumb="Dashboard"
    >
      <.td_dashboard
        id="pharmacy-dashboard"
        title="Pharmacy dashboard"
        subtitle="Pending prescriptions, dispensing, and revenue at your site."
      >
        <:actions>
          <.td_button variant="secondary" label="Scan" navigate={~p"/pharmacy/scan"} />
          <.td_button variant="secondary" label="Quick sale" navigate={~p"/pharmacy/quick-sale"} />
          <.td_button variant="primary" label="New prescription" navigate={~p"/pharmacy/prescriptions/new"} />
        </:actions>

        <:strip id="pharmacy-glances">
          <.td_glance_cell
            navigate={~p"/pharmacy/prescriptions"}
            tone="warning"
            value={phrase(length(@pending_prescriptions), "pending prescription", "pending prescriptions")}
            caption="Awaiting dispensing"
          >
            <:icon><.td_icon name="clipboard-text" class="size-[18px]" /></:icon>
          </.td_glance_cell>
          <.td_glance_cell
            navigate={~p"/pharmacy/receive-stock"}
            tone="info"
            value={phrase(@pending_batches_count, "pending batch", "pending batches")}
            caption="Awaiting receipt at your site"
          >
            <:icon><.td_icon name="package" class="size-[18px]" /></:icon>
          </.td_glance_cell>
          <.td_glance_cell
            navigate={~p"/pharmacy/transactions"}
            tone="success"
            value={"#{money(@stats.revenue_this_month)} this month"}
            caption="Wallet credits collected"
          >
            <:icon><.td_icon name="currency-circle-dollar" class="size-[18px]" /></:icon>
          </.td_glance_cell>
          <.td_glance_cell
            id="dispensed-today-card"
            tone="neutral"
            value={phrase(@dispensed_today, "unit dispensed today", "units dispensed today")}
            caption="Dispensed today"
          >
            <:icon><.td_icon name="check-circle" class="size-[18px]" /></:icon>
          </.td_glance_cell>
        </:strip>

        <.td_dash_row>
          <.td_dash_card
            id="stock-health"
            title="Stock health"
            subtitle="Your site, today"
            width={340}
          >
            <.td_tick_row
              label={phrase(length(@out_of_stock), "out of stock", "out of stock")}
              caption="Products with no remaining stock"
              count={length(@out_of_stock)}
              max={stock_health_max(@out_of_stock, @low_stock, @near_expiry, @pending_batches_count)}
              tone="danger"
              navigate={~p"/pharmacy/receive-stock"}
            />
            <.td_tick_row
              label={phrase(length(@low_stock), "low on stock", "low on stock")}
              caption="At or below reorder level"
              count={length(@low_stock)}
              max={stock_health_max(@out_of_stock, @low_stock, @near_expiry, @pending_batches_count)}
              tone="warning"
              navigate={~p"/pharmacy/stock"}
            />
            <.td_tick_row
              label={phrase(length(@near_expiry), "near-expiry batch", "near-expiry batches")}
              caption={"Expiring within #{@near_expiry_days} days"}
              count={length(@near_expiry)}
              max={stock_health_max(@out_of_stock, @low_stock, @near_expiry, @pending_batches_count)}
              tone="expiry"
              navigate={~p"/pharmacy/stock"}
            />
            <.td_tick_row
              label={phrase(@pending_batches_count, "batch to receive", "batches to receive")}
              caption="Awaiting receipt at your site"
              count={@pending_batches_count}
              max={stock_health_max(@out_of_stock, @low_stock, @near_expiry, @pending_batches_count)}
              tone="info"
              navigate={~p"/pharmacy/receive-stock"}
            />
          </.td_dash_card>

          <.td_dash_card
            id="top-products"
            title="Top dispensed products"
            subtitle="By units dispensed this month"
          >
            <div :if={@top_products != []} class="td-tick-list">
              <.td_tick_row
                :for={{name, qty} <- @top_products}
                label={name}
                count={qty}
                max={top_products_max(@top_products)}
                tone="neutral"
                navigate={~p"/pharmacy/stock"}
              />
            </div>
            <.td_empty
              :if={@top_products == []}
              id="top-products-empty"
              title="No dispensing this month"
              hint="Products will appear here once you dispense or complete a sale."
            />
          </.td_dash_card>
        </.td_dash_row>

        <.td_dash_row>
          <.td_dash_card id="out-of-stock-table" title="Out of stock" subtitle="Products with no remaining stock at your site.">
            <.table
              id="out-of-stock"
              rows={@out_of_stock}
              row_click={fn _row -> JS.navigate(~p"/pharmacy/receive-stock") end}
            >
              <:col :let={{product, _total}} label="Product">{product_name(product)}</:col>
              <:col :let={{product, _total}} label="Reorder level">{product && product.reorder_level}</:col>
              <:col :let={{_product, total}} label="Remaining">{total}</:col>
              <:empty_state>
                <.td_empty title="Nothing out of stock" hint="Every product at your site has remaining stock." />
              </:empty_state>
            </.table>
          </.td_dash_card>
        </.td_dash_row>

        <.td_dash_row>
          <.td_dash_card id="low-stock-table" title="Low stock" subtitle="Products at or below their reorder level.">
            <.table
              id="low-stock"
              rows={@low_stock}
              row_click={fn _row -> JS.navigate(~p"/pharmacy/receive-stock") end}
            >
              <:col :let={{product, _total}} label="Product">{product_name(product)}</:col>
              <:col :let={{product, _total}} label="Reorder level">{product && product.reorder_level}</:col>
              <:col :let={{_product, total}} label="Remaining">{total}</:col>
              <:empty_state>
                <.td_empty title="No products are low on stock" hint="Products will show up here once they drop to their reorder level." />
              </:empty_state>
            </.table>
          </.td_dash_card>
        </.td_dash_row>

        <.td_dash_row>
          <.td_dash_card id="near-expiry-table" title="Near-expiry batches" subtitle={"Expiring within #{@near_expiry_days} days"}>
            <.table
              id="near-expiry"
              rows={@near_expiry}
              row_click={fn batch -> JS.navigate(~p"/pharmacy/scan?gtin=#{batch.gtin}") end}
            >
              <:col :let={batch} label="Product">{product_name(@products_by_id[batch.product_id])}</:col>
              <:col :let={batch} label="Batch no.">
                <span class="td-mono">{batch.batch_no}</span>
              </:col>
              <:col :let={batch} label="Expiry">{batch.expiry_date}</:col>
              <:col :let={batch} label="Remaining">{batch.remaining_quantity}</:col>
              <:empty_state>
                <.td_empty title="No batches expiring soon" hint={"Batches will appear here within #{@near_expiry_days} days of their expiry date."} />
              </:empty_state>
            </.table>
          </.td_dash_card>
        </.td_dash_row>

        <.td_dash_row>
          <.td_dash_card id="pending-prescriptions-card" title="Pending prescriptions">
            <:actions>
              <.td_button variant="secondary" label="View all" navigate={~p"/pharmacy/prescriptions"} />
            </:actions>
            <.table
              id="pending-prescriptions"
              rows={@pending_prescriptions}
              row_click={fn prescription -> JS.navigate(~p"/pharmacy/prescriptions/#{prescription.id}") end}
            >
              <:col :let={prescription} label="Patient">{patient_label(prescription)}</:col>
              <:col :let={prescription} label="Status">
                <.status_badge status={prescription.status} />
              </:col>
              <:col :let={prescription} label="Total">{money(prescription.total_amount)}</:col>
              <:col :let={prescription} label="Paid">{paid_label(prescription.has_paid)}</:col>
              <:empty_state>
                <.td_empty
                  title="No pending prescriptions"
                  hint="Prescriptions awaiting dispensing at your site will appear here."
                />
              </:empty_state>
            </.table>
          </.td_dash_card>
        </.td_dash_row>
      </.td_dashboard>

      <Layouts.product_tour
        id="pharmacy-product-tour"
        tour_key={"thamani-pharmacy-tour-v1-#{@current_scope.user.id}"}
        auto_start={@auto_start_tour?}
        steps={product_tour_steps(@multi_site?)}
      />
    </Layouts.pharmacy_shell>
    """
  end
end
