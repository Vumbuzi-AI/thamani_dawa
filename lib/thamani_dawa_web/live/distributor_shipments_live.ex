defmodule ThamaniDawaWeb.DistributorShipmentsLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.DistributorShipments
  alias ThamaniDawaWeb.DistributorPagination

  def mount(_params, _session, socket) do
    {:ok, stream(socket, :shipments, [])}
  end

  def handle_params(%{"id" => id}, _url, socket) do
    org_id = socket.assigns.current_scope.organization_id
    shipment = DistributorShipments.get_shipment!(org_id, id)

    {:noreply,
     socket
     |> assign(:shipment, shipment)
     |> assign(:page_title, "Shipment ##{shipment.id}")}
  end

  def handle_params(params, _url, socket) do
    shipments =
      DistributorShipments.list_shipments(socket.assigns.current_scope.organization_id)

    page_info = DistributorPagination.page(shipments, DistributorPagination.page_number(params))

    {:noreply,
     socket
     |> assign(:shipment, nil)
     |> assign(:page_info, page_info)
     |> stream(:shipments, page_info.entries, reset: true)
     |> assign(:page_title, "Shipments")}
  end

  defp money(amount), do: "KES #{amount}"

  defp dispatched_at_label(nil), do: "Awaiting dispatch"

  defp dispatched_at_label(dispatched_at) do
    Calendar.strftime(dispatched_at, "%d %b %Y, %H:%M")
  end

  def render(%{live_action: :show} = assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/shipments"}
    >
      <.header icon="hero-truck">
        Shipment #{@shipment.id}
        <:subtitle>
          <.link navigate={~p"/distributor/shipments"} class="text-thamani-forest hover:underline">
            ← Back to shipments
          </.link>
        </:subtitle>
      </.header>

      <%!-- Shipment header card --%>
      <div class="mt-6 rounded-2xl border border-thamani-stone bg-white p-6 shadow-sm">
        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <div>
            <p class="text-xs font-medium uppercase tracking-wide text-thamani-pewter">Order</p>
            <p class="mt-1 text-sm font-semibold text-thamani-forest">
              <.link
                navigate={~p"/distributor/orders/#{@shipment.order.id}"}
                class="text-thamani-forest hover:underline"
              >
                Order #{@shipment.order.id}
              </.link>
            </p>
          </div>
          <div>
            <p class="text-xs font-medium uppercase tracking-wide text-thamani-pewter">Customer</p>
            <p class="mt-1 text-sm font-semibold text-thamani-forest">{@shipment.customer.name}</p>
          </div>
          <div>
            <p class="text-xs font-medium uppercase tracking-wide text-thamani-pewter">
              From warehouse
            </p>
            <p class="mt-1 text-sm text-thamani-forest">{@shipment.warehouse.name}</p>
          </div>
          <div>
            <p class="text-xs font-medium uppercase tracking-wide text-thamani-pewter">Destination</p>
            <p class="mt-1 text-sm text-thamani-forest">{@shipment.destination}</p>
          </div>
          <div>
            <p class="text-xs font-medium uppercase tracking-wide text-thamani-pewter">
              Dispatched at
            </p>
            <p class="mt-1 text-sm text-thamani-forest">
              {dispatched_at_label(@shipment.dispatched_at)}
            </p>
          </div>
        </div>
      </div>

      <%!-- Shipment lines table --%>
      <div class="mt-6 rounded-2xl border border-thamani-stone bg-white shadow-sm overflow-hidden">
        <div class="border-b border-thamani-stone px-6 py-4">
          <h2 class="text-sm font-semibold text-thamani-forest">Shipment lines</h2>
        </div>
        <table class="min-w-full divide-y divide-thamani-stone">
          <thead class="bg-thamani-stone/30">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                Product
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                Batch No.
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                Quantity
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                Unit price
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                Line total
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-thamani-stone">
            <%= for line <- @shipment.lines do %>
              <tr class="hover:bg-thamani-stone/10 transition-colors">
                <td class="px-6 py-4 text-sm text-thamani-forest">
                  {line.product.generic_name || line.product.brand_name}
                </td>
                <td class="px-6 py-4 text-sm text-thamani-pewter font-mono">
                  {line.batch.batch_no}
                </td>
                <td class="px-6 py-4 text-sm text-right text-thamani-forest">{line.quantity}</td>
                <td class="px-6 py-4 text-sm text-right text-thamani-forest">
                  {money(line.unit_price)}
                </td>
                <td class="px-6 py-4 text-sm text-right font-medium text-thamani-forest">
                  {money(line.quantity * line.unit_price)}
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <%!-- Invoice link --%>
      <%= if @shipment.order.invoice do %>
        <div class="mt-4 flex justify-end">
          <.link
            navigate={~p"/distributor/orders/#{@shipment.order.id}"}
            class="inline-flex items-center gap-1.5 text-sm font-medium text-thamani-forest hover:underline"
          >
            View order <.icon name="hero-arrow-right" class="size-4" />
          </.link>
        </div>
      <% end %>
    </Layouts.distributor_shell>
    """
  end

  def render(%{live_action: :index} = assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/shipments"}
    >
      <.header icon="hero-truck">
        Shipments
        <:subtitle>
          Every dispatch remains tied to its originating warehouse and destination.
        </:subtitle>
      </.header>
      <.table
        id="distributor-shipments"
        rows={@streams.shipments}
        row_click={fn {_id, shipment} -> JS.navigate(~p"/distributor/shipments/#{shipment.id}") end}
      >
        <:col :let={{_id, shipment}} label="Shipment">#{shipment.id}</:col>
        <:col :let={{_id, shipment}} label="Customer">{shipment.customer.name}</:col>
        <:col :let={{_id, shipment}} label="From">{shipment.warehouse.name}</:col>
        <:col :let={{_id, shipment}} label="To">{shipment.destination}</:col>
        <:col :let={{_id, shipment}} label="Dispatched">
          {dispatched_at_label(shipment.dispatched_at)}
        </:col>
        <:empty_state>
          <.blank_state icon="hero-truck" title="No shipments yet">
            Dispatched orders will appear here once they have been sent out.
          </.blank_state>
        </:empty_state>
      </.table>
      <.pagination page={@page_info} path={~p"/distributor/shipments"} />
    </Layouts.distributor_shell>
    """
  end
end
