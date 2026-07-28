defmodule ThamaniDawaWeb.LabStockProductLive do
  @moduledoc """
  Read-only list of a single product's batches at lab sites, reached by drilling
  into `LabStockLive`'s products view.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Batches
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    org_id = scope.organization_id
    sites = if Scope.admin?(scope), do: Sites.list_sites(org_id), else: scope.user.sites
    lab_sites = Enum.filter(sites, &Site.lab?/1)
    allowed_site_ids = Enum.map(lab_sites, & &1.id)

    product = Products.get_product!(org_id, id)
    batches = Batches.list_batches_for_product(org_id, id, allowed_site_ids)

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
    <Layouts.lab_shell flash={@flash} current_scope={@current_scope} current_path="/lab/stock">
      <.header icon="hero-cube">
        {product_name(@product)}
        <:subtitle>Every batch of this product across lab sites — read-only.</:subtitle>
      </.header>

      <.table
        id="batches"
        rows={@streams.batches}
        row_click={fn {_id, batch} -> JS.navigate(~p"/lab/stock/batches/#{batch.id}") end}
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
            Batches dispatched to any lab site will appear here.
          </.blank_state>
        </:empty_state>
      </.table>
    </Layouts.lab_shell>
    """
  end
end
