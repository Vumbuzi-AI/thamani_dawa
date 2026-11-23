defmodule ThamaniDawaWeb.ManufacturerInventoryLive do
  @moduledoc """
  The manufacturer's batches grouped by product, with each batch's
  serial count — "serials stored as groups of batches."
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    groups =
      organization_id
      |> Manufacturing.list_products()
      |> Enum.map(fn product ->
        {product, Manufacturing.list_batches(organization_id, product.id)}
      end)
      |> Enum.reject(fn {_product, batches} -> batches == [] end)

    {:ok,
     socket
     |> assign(:page_title, "Inventory")
     |> assign(:groups, groups)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/inventory"}
    >
      <.header icon="hero-cube">
        Inventory
        <:subtitle>Batches grouped by product, with the serials generated for each.</:subtitle>
      </.header>

      <div class="mt-4 space-y-5">
        <section
          :for={{product, batches} <- @groups}
          class="rounded-2xl border border-thamani-frosted bg-white p-5"
        >
          <div class="flex items-center justify-between gap-4">
            <div>
              <h2 class="text-sm font-semibold text-thamani-forest">{product.name}</h2>
              <p class="font-mono text-xs text-thamani-pewter">{product.gtin}</p>
            </div>
            <.button variant="ghost" navigate={~p"/manufacturer/products/#{product.id}"}>
              View product
            </.button>
          </div>

          <.table id={"manufacturer-inventory-#{product.id}"} rows={batches}>
            <:col :let={{batch, _count}} label="Batch no.">{batch.batch_no}</:col>
            <:col :let={{batch, _count}} label="Production">
              {Calendar.strftime(batch.production_date, "%d %b %Y")}
            </:col>
            <:col :let={{batch, _count}} label="Expiry">
              {Calendar.strftime(batch.expiry_date, "%d %b %Y")}
            </:col>
            <:col :let={{_batch, count}} label="Serials">{count}</:col>
          </.table>
        </section>

        <.blank_state :if={@groups == []} icon="hero-cube" title="No batches yet">
          Add a product and a batch to start tracking inventory.
        </.blank_state>
      </div>
    </Layouts.manufacturer_shell>
    """
  end
end
