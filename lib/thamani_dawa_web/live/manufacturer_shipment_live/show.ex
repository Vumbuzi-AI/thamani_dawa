defmodule ThamaniDawaWeb.ManufacturerShipmentLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, load(socket, id)}
  end

  @impl true
  def handle_event("submit", _params, socket) do
    scope = socket.assigns.current_scope

    case Manufacturing.submit_shipment(scope.organization_id, socket.assigns.shipment.id) do
      {:ok, shipment} ->
        {:noreply,
         socket
         |> assign(:shipment, shipment)
         |> put_flash(:info, "Shipment submitted for review.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Shipment could not be submitted.")}
    end
  end

  def handle_event("approve", _params, socket) do
    scope = socket.assigns.current_scope

    case Manufacturing.approve_shipment(
           scope.organization_id,
           scope.user,
           socket.assigns.shipment.id
         ) do
      {:ok, shipment} ->
        {:noreply,
         socket
         |> assign(:shipment, shipment)
         |> put_flash(:info, "Shipment approved and manufacturer EPCIS shipping event queued.")}

      {:error, {:invalid_state, "approved"}} ->
        {:noreply, put_flash(socket, :info, "This shipment has already been approved.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Shipment could not be dispatched.")}
    end
  end

  defp load(socket, id) do
    shipment = Manufacturing.get_shipment!(socket.assigns.current_scope.organization_id, id)
    socket |> assign(:shipment, shipment) |> assign(:page_title, shipment.reference)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/shipments"}
    >
      <.header icon="hero-truck" back={~p"/manufacturer/shipments"}>
        {@shipment.reference}
        <:subtitle>
          Order {@shipment.order_number} · {@shipment.reference} · {length(@shipment.shipper_ssccs)} shippers
        </:subtitle>
        <:actions>
          <.button
            :if={@shipment.status == "draft"}
            id="submit-manufacturer-shipment"
            phx-click="submit"
          >
            <.icon name="hero-paper-airplane" class="size-4" /> Submit for review
          </.button>
          <.button
            :if={@shipment.status == "submitted"}
            id="approve-manufacturer-shipment"
            phx-click="approve"
            data-confirm="Approve and dispatch this shipment?"
          >
            <.icon name="hero-check" class="size-4" /> Approve shipment
          </.button>
        </:actions>
      </.header>

      <div class="mt-4"><.shipment_status_badge status={@shipment.status} /></div>

      <div id="manufacturer-shipment-detail" class="mt-6 grid gap-5 lg:grid-cols-2">
        <section class="rounded-2xl border border-td-hairline bg-td-surface p-6 shadow-sm">
          <h2 class="font-semibold text-thamani-forest">Route</h2>
          <dl class="mt-4 space-y-4 text-sm">
            <div>
              <dt class="text-thamani-pewter">From</dt><dd class="font-medium">
                {@shipment.origin_company}
              </dd><dd class="font-mono text-xs">{@shipment.origin_gln}</dd>
            </div>
            <div>
              <dt class="text-thamani-pewter">To</dt><dd class="font-medium">
                {@shipment.destination_company}
              </dd><dd class="font-mono text-xs">{@shipment.destination_gln}</dd>
            </div>
          </dl>
        </section>
        <section class="rounded-2xl border border-td-hairline bg-td-surface p-6 shadow-sm">
          <h2 class="font-semibold text-thamani-forest">Packed logistics units</h2>
          <ul id="manufacturer-shipment-items" class="mt-4 divide-y divide-td-hairline">
            <li :for={sscc <- @shipment.shipper_ssccs} id={"shipment-sscc-#{sscc.id}"} class="py-3">
              <p class="font-mono text-sm font-semibold">{sscc.code}</p>
              <p class="text-xs text-thamani-pewter">
                GTIN {sscc.gtin || "—"} · {sscc.count_of_trade_items || 0} units
              </p>
            </li>
          </ul>
        </section>
      </div>
    </Layouts.manufacturer_shell>
    """
  end
end
