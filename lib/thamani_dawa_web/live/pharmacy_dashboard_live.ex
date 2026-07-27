defmodule ThamaniDawaWeb.PharmacyDashboardLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Dashboards
  alias ThamaniDawa.Prescriptions
  alias ThamaniDawa.Products
  alias ThamaniDawaWeb.SiteScoping

  @near_expiry_days 30

  def mount(_params, _session, socket) do
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

    {out_of_stock, low_stock} = stock_alerts(active_batches, products_by_id)

    {:ok,
     socket
     |> assign(:products_by_id, products_by_id)
     |> assign(:out_of_stock, out_of_stock)
     |> assign(:low_stock, low_stock)
     |> assign(:near_expiry, near_expiry(active_batches))
     |> assign(:near_expiry_days, @near_expiry_days)
     |> assign(:pending_batches_count, length(pending_batches))
     |> assign(:pending_prescriptions, prescriptions)
     |> assign(:stats, Dashboards.pharmacy_stats(organization_id, site_id))
     |> assign(:dispensed_by_day, Dashboards.dispensed_by_day(organization_id, site_id))
     |> assign(:top_products, Dashboards.top_dispensed_products(organization_id, site_id))}
  end

  defp stock_alerts(batches, products_by_id) do
    batches
    |> Enum.group_by(& &1.product_id)
    |> Enum.map(fn {product_id, product_batches} ->
      {products_by_id[product_id], Enum.sum(Enum.map(product_batches, & &1.remaining_quantity))}
    end)
    |> Enum.filter(fn {product, _total} -> product && product.reorder_level end)
    |> split_stock_alerts()
  end

  defp split_stock_alerts(totals) do
    {out, low} =
      Enum.reduce(totals, {[], []}, fn {product, total} = entry, {out, low} ->
        cond do
          total <= 0 -> {[entry | out], low}
          total <= product.reorder_level -> {out, [entry | low]}
          true -> {out, low}
        end
      end)

    {Enum.reverse(out), Enum.reverse(low)}
  end

  defp near_expiry(batches) do
    today = Date.utc_today()

    batches
    |> Enum.filter(fn batch ->
      batch.remaining_quantity > 0 &&
        Date.diff(batch.expiry_date, today) in 0..@near_expiry_days
    end)
    |> Enum.sort_by(& &1.expiry_date, Date)
  end

  defp product_name(nil), do: "(unknown product)"
  defp product_name(product), do: product.generic_name || product.brand_name || "(unnamed)"

  defp money(amount) do
    grouped =
      amount
      |> round()
      |> Integer.to_string()
      |> String.reverse()
      |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
      |> String.reverse()

    "KSh " <> grouped
  end

  defp dispensed_by_day_chart_data(dispensed_by_day) do
    %{
      labels: Enum.map(dispensed_by_day, fn {date, _qty} -> Calendar.strftime(date, "%d %b") end),
      datasets: [
        %{
          label: "Units dispensed",
          data: Enum.map(dispensed_by_day, fn {_date, qty} -> qty end),
          borderColor: "#6667ab",
          backgroundColor: "rgba(102, 103, 171, 0.14)",
          fill: true,
          tension: 0.3,
          pointRadius: 3
        }
      ]
    }
  end

  defp top_products_chart_data(top_products) do
    %{
      labels: Enum.map(top_products, fn {name, _qty} -> name end),
      datasets: [
        %{
          label: "Units dispensed",
          data: Enum.map(top_products, fn {_name, qty} -> qty end),
          backgroundColor: "#1f9e8f",
          borderRadius: 4
        }
      ]
    }
  end

  defp chart_options do
    %{
      responsive: true,
      maintainAspectRatio: false,
      plugins: %{legend: %{display: false}},
      scales: %{y: %{beginAtZero: true}}
    }
  end

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell flash={@flash} current_scope={@current_scope} current_path="/pharmacy">
      <.header icon="hero-squares-2x2">
        Pharmacy dashboard
        <:subtitle>Stock alerts and pending prescriptions at your site.</:subtitle>
      </.header>

      <div class="dashboard-stat-grid mt-4">
        <.stat_tile
          icon="hero-x-circle"
          label="Out of stock"
          value={length(@out_of_stock)}
          sublabel="Products with no remaining stock"
        />
        <.stat_tile
          icon="hero-exclamation-triangle"
          label="Low stock"
          value={length(@low_stock)}
          sublabel="At or below reorder level"
        />
        <.stat_tile
          icon="hero-calendar-days"
          label="Near-expiry"
          value={length(@near_expiry)}
          sublabel={"Expiring within #{@near_expiry_days} days"}
        />
        <.stat_tile
          icon="hero-document-text"
          label="Pending prescriptions"
          value={length(@pending_prescriptions)}
          sublabel="Awaiting dispensing"
        />
        <.stat_tile
          icon="hero-arrow-down-tray"
          label="Pending batches"
          value={@pending_batches_count}
          sublabel="Awaiting receipt at your site"
        />
        <.stat_tile
          icon="hero-banknotes"
          label="Revenue this month"
          value={money(@stats.revenue_this_month)}
          sublabel="Wallet credits collected"
        />
      </div>

      <div class="dashboard-chart-grid mt-6">
        <.chart_card
          id="dispensed-by-day-chart"
          title="Prescriptions dispensed"
          subtitle="Units dispensed per day, last 30 days"
          type="line"
          data={dispensed_by_day_chart_data(@dispensed_by_day)}
          options={chart_options()}
        />
        <.chart_card
          id="top-products-chart"
          title="Top dispensed products"
          subtitle="By units dispensed this month"
          type="bar"
          data={top_products_chart_data(@top_products)}
          options={chart_options()}
        />
      </div>

      <.header variant="plain" class="mt-6">
        Out of stock
        <:subtitle>Products with no remaining stock at your site</:subtitle>
      </.header>
      <.table
        id="out-of-stock"
        rows={@out_of_stock}
        row_click={fn _row -> JS.navigate(~p"/pharmacy/receive-stock") end}
      >
        <:col :let={{product, _total}} label="Product">{product_name(product)}</:col>
        <:col :let={{product, _total}} label="Reorder level">{product && product.reorder_level}</:col>
        <:col :let={{_product, total}} label="Remaining">
          <span class="text-error font-semibold">{total}</span>
        </:col>
        <:empty_state>
          <.blank_state icon="hero-check-circle" title="Nothing out of stock">
            Every product at your site has remaining stock.
          </.blank_state>
        </:empty_state>
      </.table>

      <.header variant="plain" class="mt-6">
        Low stock
        <:subtitle>Products at or below their reorder level</:subtitle>
      </.header>
      <.table
        id="low-stock"
        rows={@low_stock}
        row_click={fn _row -> JS.navigate(~p"/pharmacy/receive-stock") end}
      >
        <:col :let={{product, _total}} label="Product">{product_name(product)}</:col>
        <:col :let={{product, _total}} label="Reorder level">{product && product.reorder_level}</:col>
        <:col :let={{_product, total}} label="Remaining">{total}</:col>
        <:empty_state>
          <.blank_state icon="hero-check-circle" title="No products are low on stock">
            Products will show up here once they drop to their reorder level.
          </.blank_state>
        </:empty_state>
      </.table>

      <.header variant="plain" class="mt-6">
        Near-expiry batches
        <:subtitle>Expiring within {@near_expiry_days} days</:subtitle>
      </.header>
      <.table
        id="near-expiry"
        rows={@near_expiry}
        row_click={fn batch -> JS.navigate(~p"/pharmacy/scan?gtin=#{batch.gtin}") end}
      >
        <:col :let={batch} label="Product">{product_name(@products_by_id[batch.product_id])}</:col>
        <:col :let={batch} label="Batch no.">{batch.batch_no}</:col>
        <:col :let={batch} label="Expiry">{batch.expiry_date}</:col>
        <:col :let={batch} label="Remaining">{batch.remaining_quantity}</:col>
        <:empty_state>
          <.blank_state icon="hero-calendar-days" title="No batches expiring soon">
            Batches will appear here within {@near_expiry_days} days of their expiry date.
          </.blank_state>
        </:empty_state>
      </.table>

      <.header variant="plain" class="mt-6">
        Pending prescriptions
      </.header>
      <.table
        id="pending-prescriptions"
        rows={@pending_prescriptions}
        row_click={fn prescription -> JS.navigate(~p"/pharmacy/prescriptions/#{prescription.id}") end}
      >
        <:col :let={prescription} label="Status">
          <.status_badge status={prescription.status} />
        </:col>
        <:col :let={prescription} label="Total">{prescription.total_amount}</:col>
        <:col :let={prescription} label="Paid">
          {if prescription.has_paid, do: "Yes", else: "No"}
        </:col>
        <:empty_state>
          <.blank_state icon="hero-clipboard-document-check" title="No pending prescriptions">
            Prescriptions awaiting dispensing at your site will appear here.
          </.blank_state>
        </:empty_state>
      </.table>
    </Layouts.pharmacy_shell>
    """
  end
end
