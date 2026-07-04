defmodule ThamaniDawaWeb.ProductLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Products

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    product = Products.get_product!(organization_id, id)

    batches =
      organization_id
      |> Batches.list_batches()
      |> Enum.filter(&(&1.product_id == product.id))

    {:ok, assign(socket, product: product, batches: batches)}
  end

  defp product_name(product), do: product.generic_name || product.name || "(unnamed)"

  def render(assigns) do
    ~H"""
    <Layouts.app_shell flash={@flash} current_scope={@current_scope}>
      <.header>
        {product_name(@product)}
        <:actions>
          <.button navigate={~p"/pharmacy/products/#{@product.id}/edit"}>Edit</.button>
          <.button navigate={~p"/pharmacy/products"}>Back</.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Type">{Phoenix.Naming.humanize(@product.product_type)}</:item>
        <:item title="Brand name">{@product.brand_name}</:item>
        <:item title="Category">{@product.category}</:item>
        <:item title="Unit of measure">{@product.uom}</:item>
        <:item title="GTIN">{@product.gtin}</:item>
        <:item title="OTC">{if @product.is_otc, do: "Yes", else: "No"}</:item>
        <:item title="Dangerous drug">{if @product.is_dangerous_drug, do: "Yes", else: "No"}</:item>
        <:item title="Reorder level">{@product.reorder_level}</:item>
      </.list>

      <.header class="mt-6">Batches</.header>
      <.table id="batches" rows={@batches}>
        <:col :let={batch} label="Batch no.">{batch.batch_no}</:col>
        <:col :let={batch} label="Expiry">{batch.expiry}</:col>
        <:col :let={batch} label="Remaining">{batch.remaining_quantity}</:col>
        <:col :let={batch} label="Active">{if batch.is_active, do: "Yes", else: "No"}</:col>
      </.table>
    </Layouts.app_shell>
    """
  end
end
