defmodule ThamaniDawaWeb.ManufacturerShipmentLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Sites

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    site = Sites.get_site!(scope.organization_id, scope.current_site_id)

    {:ok,
     socket
     |> assign(:page_title, "Manufacturer shipments")
     |> assign(:site, site)
     |> assign(:form, shipment_form(site.gln))
     |> load()}
  end

  @impl true
  def handle_event("validate", %{"shipment" => params}, socket) do
    form =
      params
      |> Map.drop(["sscc_ids"])
      |> then(&Manufacturing.change_shipment(%ThamaniDawa.Manufacturing.Shipment{}, &1))
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("create", %{"shipment" => params}, socket) do
    {sscc_ids, attrs} = Map.pop(params, "sscc_ids", [])
    scope = socket.assigns.current_scope

    case Manufacturing.create_shipment(scope.organization_id, scope.user, attrs, sscc_ids) do
      {:ok, shipment} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Shipment created. Review it, then dispatch when it leaves the plant."
         )
         |> push_navigate(to: ~p"/manufacturer/shipments/#{shipment.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(%{changeset | action: :insert}))}

      {:error, :no_ssccs} ->
        {:noreply, put_flash(socket, :error, "Select at least one available SSCC.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "The selected SSCCs are no longer available.")}
    end
  end

  defp load(socket) do
    organization_id = socket.assigns.current_scope.organization_id

    socket
    |> assign(:shipments, Manufacturing.list_shipments(organization_id))
    |> assign(:available_ssccs, Manufacturing.list_available_ssccs(organization_id))
  end

  defp shipment_form(origin_gln) do
    to_form(
      Manufacturing.change_shipment(%ThamaniDawa.Manufacturing.Shipment{}, %{
        origin_gln: origin_gln
      })
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/shipments"}
    >
      <.td_list_page
        title="Manufacturer shipments"
        subtitle="Dispatch packed SSCCs and report the EPCIS shipping event."
      >
        <section
          id="new-manufacturer-shipment"
          class="mt-6 rounded-2xl border border-td-hairline bg-td-surface p-6 shadow-sm"
        >
          <h2 class="text-lg font-semibold text-thamani-forest">Prepare a shipment</h2>
          <.form
            for={@form}
            id="manufacturer-shipment-form"
            phx-change="validate"
            phx-submit="create"
            class="mt-5 space-y-5"
          >
            <div class="grid gap-4 md:grid-cols-3">
              <.input field={@form[:order_number]} label="Order / dispatch number" />
              <.input field={@form[:origin_gln]} label="Ship-from GLN" readonly />
              <.input field={@form[:destination_gln]} label="Destination GLN" />
            </div>

            <fieldset>
              <legend class="text-sm font-semibold text-thamani-forest">
                Available packed SSCCs
              </legend>
              <div
                id="manufacturer-shipment-ssccs"
                class="mt-3 grid gap-3 md:grid-cols-2 xl:grid-cols-3"
              >
                <label
                  :for={sscc <- @available_ssccs}
                  class="flex cursor-pointer items-start gap-3 rounded-xl border border-td-hairline p-4 transition hover:border-td-warning-line hover:bg-td-warning-tint"
                >
                  <input
                    type="checkbox"
                    name="shipment[sscc_ids][]"
                    value={sscc.id}
                    class="mt-1 size-4 rounded border-td-hairline text-thamani-forest"
                  />
                  <span>
                    <span class="block font-mono text-sm font-semibold text-thamani-forest">{sscc.code}</span>
                    <span class="mt-1 block text-xs text-thamani-pewter">GTIN {sscc.gtin || "—"} · {sscc.count_of_trade_items ||
                      0} units</span>
                  </span>
                </label>
                <p :if={@available_ssccs == []} class="text-sm text-thamani-pewter">
                  No unshipped SSCCs are available. Pack an SSCC first.
                </p>
              </div>
            </fieldset>
            <.button id="create-manufacturer-shipment" type="submit" disabled={@available_ssccs == []}>
              <.icon name="hero-plus" class="size-4" /> Create shipment
            </.button>
          </.form>
        </section>

        <section class="mt-8">
          <h2 class="dashboard-section-label">Shipment history</h2>
          <.table id="manufacturer-shipments" rows={@shipments}>
            <:col :let={shipment} label="Reference">
              <.link
                navigate={~p"/manufacturer/shipments/#{shipment.id}"}
                class="font-semibold text-thamani-forest hover:underline"
              >{shipment.reference}</.link>
            </:col>
            <:col :let={shipment} label="Order">{shipment.order_number}</:col>
            <:col :let={shipment} label="Destination">{shipment.destination_company}</:col>
            <:col :let={shipment} label="SSCCs">{length(shipment.shipper_ssccs)}</:col>
            <:col :let={shipment} label="Status">
              <.shipment_status_badge status={shipment.status} />
            </:col>
          </.table>
        </section>
      </.td_list_page>
    </Layouts.manufacturer_shell>
    """
  end
end
