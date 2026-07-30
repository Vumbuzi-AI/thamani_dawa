defmodule ThamaniDawaWeb.PharmacyStockProductLive do
  @moduledoc """
  Read-only list of a single product's batches, reached by drilling into
  `PharmacyStockLive`'s products view. Organization-wide like its parent —
  shows batches at every site, not just the pharmacist's home site.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Products

  def mount(%{"id" => id}, _session, socket) do
    org_id = socket.assigns.current_scope.organization_id
    product = Products.get_product!(org_id, id)
    batches = Batches.list_batches_for_product(org_id, id)

    {:ok,
     socket
     |> assign(:product, product)
     |> stream(:batches, batches)}
  end

  defp product_name(product), do: product.generic_name || product.brand_name || "(unnamed)"
  defp site_name(nil), do: "(unknown site)"
  defp site_name(site), do: site.name
  defp supplier_name(nil), do: "—"
  defp supplier_name(supplier), do: supplier.name

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/pharmacy/stock"
      back={~p"/pharmacy/stock"}
    >
      <.header icon="hero-cube">
        {product_name(@product)}
        <:subtitle>Every batch of this product, across every site — read-only.</:subtitle>
      </.header>

      <.table
        id="batches"
        rows={@streams.batches}
        row_click={fn {_id, batch} -> JS.navigate(~p"/pharmacy/stock/batches/#{batch.id}") end}
      >
        <:col :let={{_id, batch}} label="Site">{site_name(batch.site)}</:col>
        <:col :let={{_id, batch}} label="Batch no.">{batch.batch_no}</:col>
        <:col :let={{_id, batch}} label="Expiry">{batch.expiry_date}</:col>
        <:col :let={{_id, batch}} label="Remaining">{batch.remaining_quantity}</:col>
        <:col :let={{_id, batch}} label="Supplier">{supplier_name(batch.supplier)}</:col>
        <:col :let={{_id, batch}} label="Status">
          <.status_badge status={if batch.approver_id, do: :active, else: :pending_receipt} />
        </:col>
        <:empty_state>
          <.blank_state icon="hero-cube" title="No batches for this product yet">
            Batches dispatched to any site will appear here.
          </.blank_state>
        </:empty_state>
      </.table>
    </Layouts.pharmacy_shell>
    """
  end
end
