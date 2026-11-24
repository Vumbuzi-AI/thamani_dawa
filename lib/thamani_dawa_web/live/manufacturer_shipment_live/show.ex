defmodule ThamaniDawaWeb.ManufacturerShipmentLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, socket |> load(id) |> assign(:confirming?, false)}
  end

  def handle_event("open_dispatch", _params, socket) do
    {:noreply, assign(socket, :confirming?, true)}
  end

  def handle_event("cancel_dispatch", _params, socket) do
    {:noreply, assign(socket, :confirming?, false)}
  end

  def handle_event("dispatch", _params, socket) do
    scope = socket.assigns.current_scope
    id = socket.assigns.shipment.id

    result =
      case socket.assigns.shipment.status do
        "draft" ->
          with {:ok, _} <- Manufacturing.submit_shipment(scope.organization_id, id) do
            Manufacturing.approve_shipment(scope.organization_id, scope.user, id)
          end

        "submitted" ->
          Manufacturing.approve_shipment(scope.organization_id, scope.user, id)

        status ->
          {:error, {:invalid_state, status}}
      end

    case result do
      {:ok, shipment} ->
        {:noreply,
         socket
         |> assign(:shipment, shipment)
         |> assign(:confirming?, false)
         |> put_flash(:info, "Shipment dispatched.")}

      {:error, {:invalid_state, "approved"}} ->
        {:noreply, put_flash(socket, :info, "This shipment has already been dispatched.")}

      {:error, _reason} ->
        {:noreply,
         assign(socket, confirming?: false)
         |> put_flash(:error, "Shipment could not be dispatched.")}
    end
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
      <.td_back_link
        id="packed-shipment-back"
        to={~p"/manufacturer/shipments"}
        label="Back to Shipments"
      />
      <.td_page_header
        title={@shipment.reference}
        subtitle={"Order #{@shipment.order_number} · #{length(@shipment.shipper_ssccs)} shippers"}
      >
        <:actions>
          <.td_button
            :if={@shipment.status in ["draft", "submitted"]}
            id="dispatch-shipment"
            variant="primary"
            label="Dispatch shipment"
            phx-click="open_dispatch"
          />
          <.td_button
            :if={pallet_id(@shipment)}
            id="packed-shipment-pallet"
            label="Pallet"
            navigate={~p"/manufacturer/aggregations/pallets/#{pallet_id(@shipment)}"}
          />
        </:actions>
      </.td_page_header>

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

      <.td_modal
        :if={@confirming?}
        id="dispatch-shipment-modal"
        show
        title="Dispatch shipment"
        subtitle={@shipment.reference}
        on_cancel={JS.push("cancel_dispatch")}
      >
        <:body>
          <p class="td-note">
            This dispatches {@shipment.reference} for order {@shipment.order_number}. It does not create another shipment.
          </p>
        </:body>
        <:footer>
          <.td_button label="Cancel" phx-click="cancel_dispatch" />
          <.td_button
            id="confirm-dispatch"
            variant="primary"
            label="Dispatch shipment"
            phx-click="dispatch"
          />
        </:footer>
      </.td_modal>
    </Layouts.manufacturer_shell>
    """
  end

  defp pallet_id(shipment) do
    Enum.find_value(shipment.shipper_ssccs, fn sscc -> sscc.pallet && sscc.pallet.id end)
  end
end
