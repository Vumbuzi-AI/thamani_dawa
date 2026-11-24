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
      crumb="Inventory"
    >
      <.td_list_page
        title="Inventory"
        subtitle="Batches grouped by product, with the serials generated for each."
      >
        <section :for={{product, batches} <- @groups} id={"manufacturer-inventory-#{product.id}"}>
          <.td_card_header title={product.name} subtitle={product.gtin}>
            <:actions>
              <.td_button
                variant="secondary"
                label="View product"
                navigate={~p"/manufacturer/products/#{product.id}"}
              />
            </:actions>
          </.td_card_header>
          <.td_data_table
            id={"manufacturer-inventory-rows-#{product.id}"}
            rows={batches}
            row_id={fn {batch, _} -> "inventory-batch-#{batch.id}" end}
          >
            <:col :let={{batch, _count}} label="Batch no.">{batch.batch_no}</:col>
            <:col :let={{batch, _count}} label="Production">
              {ThamaniDawaWeb.TimeFormat.date(batch.production_date)}
            </:col>
            <:col :let={{batch, _count}} label="Expiry">
              {ThamaniDawaWeb.TimeFormat.date(batch.expiry_date)}
            </:col>
            <:col :let={{_batch, count}} label="Serials">{count}</:col>
          </.td_data_table>
        </section>
        <.td_empty
          :if={@groups == []}
          icon="stack"
          title="No batches yet"
          hint="Generate serials for a product and the batch shows up here."
        >
          <:action>
            <.td_button
              id="inventory-go-products"
              variant="secondary"
              glyph="arrow-right"
              label="Go to products"
              navigate={~p"/manufacturer/products"}
            />
          </:action>
        </.td_empty>
      </.td_list_page>
    </Layouts.manufacturer_shell>
    """
  end
end
