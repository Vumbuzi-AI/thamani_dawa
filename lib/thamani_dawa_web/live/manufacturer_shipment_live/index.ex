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
     |> assign(:gs1_api_key, ThamaniDawa.Organizations.gs1_api_key(scope.organization_id))
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
           "Shipment created. Dispatch it when it leaves the plant to send the EPCIS event."
         )
         |> push_navigate(to: ~p"/manufacturer/shipments/packed/#{shipment.id}")}

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
    |> assign(:available_ssccs, Manufacturing.list_available_ssccs(organization_id))
  end

  defp sscc_title(sscc) do
    labels =
      sscc.batches
      |> Enum.map(fn batch ->
        [batch.product && batch.product.name, batch.batch_no]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" · ")
      end)
      |> Enum.reject(&(&1 == ""))

    case labels do
      [] -> sscc.batch || "Packed shipper"
      _ -> Enum.join(labels, " · ")
    end
  end

  defp pallet_label(%{pallet: %{code: code}}) when is_binary(code) and code != "", do: code
  defp pallet_label(_), do: "Standalone"

  defp date_label(nil), do: "—"
  defp date_label(%Date{} = date), do: Date.to_iso8601(date)

  defp count_phrase(1, noun), do: "1 #{noun}"
  defp count_phrase(count, noun), do: "#{count} #{noun}s"

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
      crumb_parent="Shipments"
      crumb="Create"
    >
      <.td_list_page
        title="Create shipment"
        subtitle="Select the packed SSCCs leaving the plant. Dispatch sends the EPCIS shipping event."
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
              <.live_component
                module={ThamaniDawaWeb.GlnSearchField}
                id="destination-gln-search"
                name="shipment[destination_gln]"
                label="Destination GLN (ship to)"
                api_token={@gs1_api_key}
                required
              />
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
                  <span class="min-w-0 flex-1">
                    <span class="flex items-start justify-between gap-3">
                      <span class="min-w-0">
                        <span class="block truncate text-sm font-semibold text-thamani-forest">
                          {sscc_title(sscc)}
                        </span>
                        <span class="td-mono mt-0.5 block truncate text-xs text-thamani-pewter">
                          SSCC {sscc.code}
                        </span>
                      </span>
                      <span class="shrink-0 rounded-lg bg-td-wash px-2 py-1 text-xs font-medium text-thamani-forest">
                        {count_phrase(sscc.count_of_trade_items || 0, "unit")}
                      </span>
                    </span>
                    <span class="mt-3 grid grid-cols-2 gap-x-4 gap-y-1.5 text-xs text-thamani-pewter">
                      <span class="truncate"><b class="font-medium">Order</b> {sscc.order_number ||
                        "—"}</span>
                      <span class="truncate"><b class="font-medium">Pallet</b> {pallet_label(sscc)}</span>
                      <span class="truncate"><b class="font-medium">Ship to</b> {sscc.to_company_name ||
                        "—"}</span>
                      <span class="truncate"><b class="font-medium">Expires</b> {date_label(
                        sscc.expiry_date
                      )}</span>
                    </span>
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
      </.td_list_page>
    </Layouts.manufacturer_shell>
    """
  end
end
