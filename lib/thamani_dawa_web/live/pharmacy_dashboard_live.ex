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
    batches = organization_id |> Batches.list_batches() |> SiteScoping.for_current_site(scope)

    prescriptions =
      organization_id
      |> Prescriptions.list_prescriptions()
      |> SiteScoping.for_current_site(scope)
      |> Enum.filter(&(&1.status in [:pending, :partially_dispensed]))

    {:ok,
     socket
     |> assign(:products_by_id, products_by_id)
     |> assign(:low_stock, low_stock(batches, products_by_id))
     |> assign(:near_expiry, near_expiry(batches))
     |> assign(:near_expiry_days, @near_expiry_days)
     |> assign(:pending_prescriptions, prescriptions)}
  end

  defp low_stock(batches, products_by_id) do
    batches
    |> Enum.group_by(& &1.product_id)
    |> Enum.map(fn {product_id, product_batches} ->
      {products_by_id[product_id], Enum.sum(Enum.map(product_batches, & &1.remaining_quantity))}
    end)
    |> Enum.filter(fn {product, total} ->
      product && product.reorder_level && total <= product.reorder_level
    end)
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
      <.header>Pharmacy dashboard</.header>

      <.header class="mt-4">
        Low stock
        <:subtitle>Products at or below their reorder level</:subtitle>
      </.header>
      <.table id="low-stock" rows={@low_stock}>
        <:col :let={{product, _total}} label="Product">{product_name(product)}</:col>
        <:col :let={{product, _total}} label="Reorder level">{product && product.reorder_level}</:col>
        <:col :let={{_product, total}} label="Remaining">{total}</:col>
      </.table>

      <.header class="mt-6">
        Near-expiry batches
        <:subtitle>Expiring within {@near_expiry_days} days</:subtitle>
      </.header>
      <.table id="near-expiry" rows={@near_expiry}>
        <:col :let={batch} label="Product">{product_name(@products_by_id[batch.product_id])}</:col>
        <:col :let={batch} label="Batch no.">{batch.batch_no}</:col>
        <:col :let={batch} label="Expiry">{batch.expiry_date}</:col>
        <:col :let={batch} label="Remaining">{batch.remaining_quantity}</:col>
      </.table>

      <.header class="mt-6">
        Pending prescriptions
      </.header>
      <.table
        id="pending-prescriptions"
        rows={@pending_prescriptions}
        row_click={fn prescription -> JS.navigate(~p"/pharmacy/prescriptions/#{prescription.id}") end}
      >
        <:col :let={prescription} label="Status">{Phoenix.Naming.humanize(prescription.status)}</:col>
        <:col :let={prescription} label="Total">{prescription.total_amount}</:col>
        <:col :let={prescription} label="Paid">
          {if prescription.has_paid, do: "Yes", else: "No"}
        </:col>
      </.table>
    </Layouts.pharmacy_shell>
    """
  end
end
