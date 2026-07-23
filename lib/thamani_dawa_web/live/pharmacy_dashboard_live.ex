defmodule ThamaniDawaWeb.PharmacyDashboardLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Prescriptions
  alias ThamaniDawa.Products
  alias ThamaniDawaWeb.SiteScoping

  @near_expiry_days 30

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id

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
     |> assign(:pending_prescriptions, prescriptions)}
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

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell flash={@flash} current_scope={@current_scope} current_path="/pharmacy">
      <.header icon="hero-squares-2x2">
        Pharmacy dashboard
        <:subtitle>Stock alerts and pending prescriptions at your site.</:subtitle>
      </.header>

      <div
        :if={@pending_batches_count > 0}
        class="mt-4 flex items-center justify-between rounded-lg border border-amber-200 bg-amber-50 px-4 py-3"
      >
        <span class="text-sm text-amber-800">
          <strong>{@pending_batches_count}</strong>
          {if @pending_batches_count == 1, do: "batch is", else: "batches are"} awaiting receipt at your site.
        </span>
        <.thamani_btn navigate={~p"/pharmacy/receive-stock"} class="!w-auto">
          Receive stock
        </.thamani_btn>
      </div>

      <.header class="mt-6">
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

      <.header class="mt-6">
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

      <.header class="mt-6">
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

      <.header class="mt-6">
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
