defmodule ThamaniDawaWeb.ManufacturerShipmentLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> load(id)
     |> assign(:confirming?, false)
     |> assign(:expanded_ssccs, MapSet.new())}
  end

  def handle_event("open_dispatch", _params, socket) do
    {:noreply, assign(socket, :confirming?, true)}
  end

  def handle_event("cancel_dispatch", _params, socket) do
    {:noreply, assign(socket, :confirming?, false)}
  end

  def handle_event("toggle_sscc", %{"id" => id}, socket) do
    {:noreply, toggle_assign(socket, :expanded_ssccs, id)}
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
         |> assign_shipment(shipment)
         |> assign(:confirming?, false)
         |> put_flash(:info, "Shipment dispatched.")}

      {:error, {:invalid_state, "approved"}} ->
        {:noreply, put_flash(socket, :info, "This shipment has already been dispatched.")}

      {:error, _reason} ->
        {:noreply,
         put_flash(
           assign(socket, confirming?: false),
           :error,
           "Shipment could not be dispatched."
         )}
    end
  end

  @impl true
  def handle_event("submit", _params, socket) do
    scope = socket.assigns.current_scope

    case Manufacturing.submit_shipment(scope.organization_id, socket.assigns.shipment.id) do
      {:ok, shipment} ->
        {:noreply,
         socket
         |> assign_shipment(shipment)
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
         |> assign_shipment(shipment)
         |> put_flash(:info, "Shipment approved and manufacturer EPCIS shipping event queued.")}

      {:error, {:invalid_state, "approved"}} ->
        {:noreply, put_flash(socket, :info, "This shipment has already been approved.")}

      {:error, _reason} ->
        {:noreply,
         put_flash(
           assign(socket, confirming?: false),
           :error,
           "Shipment could not be dispatched."
         )}
    end
  end

  defp load(socket, id) do
    shipment = Manufacturing.get_shipment!(socket.assigns.current_scope.organization_id, id)

    socket
    |> assign_shipment(shipment)
    |> assign(:page_title, shipment.reference)
  end

  defp assign_shipment(socket, shipment) do
    socket
    |> assign(:shipment, shipment)
    |> assign(:unit_count, unit_count(shipment))
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
        subtitle={header_sub(@shipment, @unit_count)}
      >
        <:status><.shipment_status_badge status={@shipment.status} /></:status>
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

      <div class="no-print td-recipe td-list-page td-detail-page" id="manufacturer-shipment-detail">
        <div class="td-pad td-stack">
          <div
            :if={@shipment.status == "draft"}
            id="packed-shipment-draft-note"
            class="td-ban is-info"
          >
            <.td_icon name="info" />
            <span>
              Nothing has shipped yet. Dispatch records the shipping event and locks this shipment.
            </span>
          </div>

          <div class="grid gap-4 md:grid-cols-2">
            <section class="td-card td-party-card" id="packed-shipment-origin">
              <span class="td-k"><.td_icon name="factory" /> From</span>
              <span class="td-v">{@shipment.origin_company || "—"}</span>
              <span class="td-mono">GLN {@shipment.origin_gln || "—"}</span>
              <span :if={@shipment.origin_address} class="td-a">{@shipment.origin_address}</span>
              <span class="td-note">Created by {actor(@shipment.created_by)}</span>
            </section>
            <section class="td-card td-party-card" id="packed-shipment-destination">
              <span class="td-k"><.td_icon name="warehouse" /> To</span>
              <span class="td-v">{@shipment.destination_company || "—"}</span>
              <span class="td-mono">GLN {@shipment.destination_gln || "—"}</span>
              <span :if={@shipment.destination_address} class="td-a">
                {@shipment.destination_address}
              </span>
              <span class="td-note">Shipped by {actor(@shipment.shipped_by)}</span>
            </section>
          </div>

          <section class="td-card" id="packed-shipment-packing">
            <div :if={@shipment.shipper_ssccs == []} class="td-pad">
              <.td_empty
                title="Nothing packed yet"
                hint="Shippers are added from packed SSCCs before dispatch."
              />
            </div>

            <div :if={@shipment.shipper_ssccs != []} class="td-packing-sections">
              <section
                :if={pallet_groups(@shipment) != []}
                class="td-packing-section"
                aria-labelledby="shipment-pallets-heading"
              >
                <div class="td-packing-section-header">
                  <div>
                    <h3 id="shipment-pallets-heading">Pallets</h3>
                    <p>Pallets and their included shippers</p>
                  </div>
                  <span class="td-note">{count_phrase(length(pallet_groups(@shipment)), "pallet")}</span>
                </div>

                <div class="td-packing-table-wrap">
                  <table class="td-packing-table" id="shipment-pallets-table">
                    <thead>
                      <tr>
                        <th>Pallet</th>
                        <th>Included shippers</th>
                        <th class="is-num">Units</th>
                        <th>Verified</th>
                        <th><span class="sr-only">Actions</span></th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr
                        :for={group <- pallet_groups(@shipment)}
                        id={"shipment-pallet-#{group.pallet.id}"}
                      >
                        <td>
                          <.td_pid
                            id={"shipment-pallet-id-#{group.pallet.id}"}
                            label={pallet_label(group.pallet)}
                            mono
                            navigate={~p"/manufacturer/aggregations/pallets/#{group.pallet.id}"}
                          >
                            <:peek>
                              <.td_peek
                                kind="Pallet"
                                title={pallet_label(group.pallet)}
                                subtitle={count_phrase(length(group.shippers), "shipper")}
                                icon="cube"
                                mono
                              >
                                <:row label="Units">{units_for(group.shippers)}</:row>
                                <:row label="Verified">{eat(group.pallet.verified_at)}</:row>
                              </.td_peek>
                            </:peek>
                          </.td_pid>
                        </td>
                        <td>
                          <div class="td-included-shippers">
                            <.link
                              :for={sscc <- group.shippers}
                              navigate={~p"/manufacturer/aggregations/ssccs/#{sscc.id}"}
                              class="td-code-chip td-mono"
                            >
                              {sscc.code}
                            </.link>
                          </div>
                        </td>
                        <td class="is-num">{units_for(group.shippers)}</td>
                        <td>{eat(group.pallet.verified_at)}</td>
                        <td class="is-num">
                          <.td_button
                            id={"view-pallet-#{group.pallet.id}"}
                            variant="secondary"
                            label="View"
                            navigate={~p"/manufacturer/aggregations/pallets/#{group.pallet.id}"}
                          />
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </section>

              <section class="td-packing-section" aria-labelledby="shipment-shippers-heading">
                <div class="td-packing-section-header">
                  <div>
                    <h3 id="shipment-shippers-heading">Shippers</h3>
                    <p>All shippers and their packed serials</p>
                  </div>
                  <span class="td-note">{count_phrase(length(@shipment.shipper_ssccs), "shipper")}</span>
                </div>

                <div class="td-packing-table-wrap">
                  <table
                    class={[
                      "td-packing-table td-shippers-table",
                      pallet_groups(@shipment) == [] && "is-without-pallets"
                    ]}
                    id="shipment-shippers-table"
                  >
                    <thead>
                      <tr>
                        <th>Shipper</th>
                        <th :if={pallet_groups(@shipment) != []}>Pallet</th>
                        <th>Product &amp; batch</th>
                        <th>Production &amp; expiry</th>
                        <th>Serials</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for sscc <- @shipment.shipper_ssccs do %>
                        <tr class="td-shipper-row" id={"shipment-sscc-#{sscc.id}"}>
                          <td class="td-shipper-identity">
                            <div class="td-shipper-cell">
                              <.td_pid
                                id={"shipment-sscc-id-#{sscc.id}"}
                                label={sscc.code}
                                mono
                                navigate={~p"/manufacturer/aggregations/ssccs/#{sscc.id}"}
                              >
                                <:peek>
                                  <.td_peek
                                    kind="Shipper SSCC"
                                    title={sscc.code}
                                    subtitle={product_batch(sscc)}
                                    icon="cube"
                                    mono
                                  >
                                    <:row label="GTIN" mono>{sscc.gtin || "—"}</:row>
                                    <:row label="Units">
                                      {sscc.count_of_trade_items || 0}
                                    </:row>
                                    <:action>
                                      <.td_button
                                        label="Open SSCC"
                                        navigate={~p"/manufacturer/aggregations/ssccs/#{sscc.id}"}
                                      />
                                    </:action>
                                  </.td_peek>
                                </:peek>
                              </.td_pid>
                            </div>
                            <span class="td-sub td-mono">GTIN {sscc.gtin || "—"}</span>
                          </td>
                          <td :if={pallet_groups(@shipment) != []}>
                            <%= if sscc.pallet do %>
                              <.link
                                navigate={~p"/manufacturer/aggregations/pallets/#{sscc.pallet.id}"}
                                class="td-mono td-table-link"
                              >
                                {pallet_label(sscc.pallet)}
                              </.link>
                            <% else %>
                              <span class="td-note">Standalone</span>
                            <% end %>
                          </td>
                          <td class="td-product-cell">{product_batch(sscc)}</td>
                          <td class="td-date-cell">
                            <span>
                              <span class="td-k">Produced</span>
                              {formatted_date(sscc.production_date)}
                            </span>
                            <span>
                              <span class="td-k">Expires</span>
                              {formatted_date(sscc.expiry_date)}
                            </span>
                          </td>
                          <td>
                            <button
                              type="button"
                              class="td-row-toggle"
                              id={"expand-sscc-#{sscc.id}"}
                              phx-click="toggle_sscc"
                              phx-value-id={sscc.id}
                              aria-expanded={expanded?(@expanded_ssccs, to_string(sscc.id))}
                              aria-controls={"shipper-serials-#{sscc.id}"}
                              aria-label="Toggle serials"
                            >
                              <span class="td-row-chevron" aria-hidden="true">›</span>
                              <span>{count_phrase(length(serials(sscc)), "serial")}</span>
                            </button>
                          </td>
                        </tr>
                        <tr
                          :if={expanded?(@expanded_ssccs, to_string(sscc.id))}
                          class="td-serials-row"
                          id={"shipper-serials-#{sscc.id}"}
                        >
                          <td colspan={if(pallet_groups(@shipment) == [], do: "4", else: "5")}>
                            <div class="td-serials-panel">
                              <span class="td-k">
                                {count_phrase(length(serials(sscc)), "serial")}
                              </span>
                              <div class="td-serials-list">
                                <%= for serial <- Enum.take(serials(sscc), 25) do %>
                                  <span class="td-serial-chip td-mono">{serial}</span>
                                <% end %>
                                <span :if={serials(sscc) == []} class="td-note">
                                  No serials recorded
                                </span>
                                <.link
                                  :if={length(serials(sscc)) > 25}
                                  navigate={~p"/manufacturer/aggregations/ssccs/#{sscc.id}"}
                                  class="td-note"
                                >
                                  View all serials →
                                </.link>
                              </div>
                            </div>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              </section>
            </div>
          </section>

          <section class="td-card" id="packed-shipment-lifecycle">
            <.td_card_header title="Lifecycle" subtitle="Times in EAT" />
            <ol class="td-list is-pad">
              <li class="td-li">
                <.td_orb seed={actor(@shipment.created_by)} size={24} />
                <div class="td-li-g">
                  <b>Shipment created</b>
                  <span>{actor(@shipment.created_by)} · {eat(@shipment.inserted_at)}</span>
                </div>
              </li>
              <li :if={packed_at(@shipment)} class="td-li">
                <.td_orb seed="packer" size={24} />
                <div class="td-li-g">
                  <b>Units packed and verified</b>
                  <span>{eat(packed_at(@shipment))}</span>
                </div>
              </li>
              <li :if={@shipment.status == "approved"} class="td-li">
                <.td_orb seed={actor(@shipment.shipped_by)} size={24} />
                <div class="td-li-g">
                  <b>Dispatched</b>
                  <span>{actor(@shipment.shipped_by)} · {eat(@shipment.shipped_at)}</span>
                </div>
              </li>
              <li :if={@shipment.status == "rejected"} class="td-li">
                <.td_orb seed="rejected" size={24} />
                <div class="td-li-g">
                  <b>Rejected</b>
                  <span>{status_label(@shipment.status)}</span>
                </div>
              </li>
            </ol>
          </section>
        </div>
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

  defp pallet_label(nil), do: "Standalone"
  defp pallet_label(%{code: code}) when is_binary(code) and code != "", do: code
  defp pallet_label(_), do: "—"

  defp packing_groups(shipment) do
    shipment.shipper_ssccs
    |> Enum.group_by(fn sscc -> sscc.manufacturer_pallet_id || :standalone end)
    |> Enum.map(fn
      {:standalone, shippers} -> %{pallet: nil, shippers: shippers}
      {_pallet_id, [first | _] = shippers} -> %{pallet: first.pallet, shippers: shippers}
    end)
    |> Enum.sort_by(fn group -> is_nil(group.pallet) end)
  end

  defp pallet_groups(shipment) do
    shipment
    |> packing_groups()
    |> Enum.reject(&is_nil(&1.pallet))
  end

  defp expanded?(expanded, id), do: MapSet.member?(expanded, id)

  defp toggle_assign(socket, key, id) do
    expanded = socket.assigns[key]

    expanded =
      if MapSet.member?(expanded, id),
        do: MapSet.delete(expanded, id),
        else: MapSet.put(expanded, id)

    assign(socket, key, expanded)
  end

  defp count_phrase(1, noun), do: "1 #{noun}"
  defp count_phrase(count, noun), do: "#{count} #{noun}s"

  defp header_sub(shipment, unit_count) do
    [
      "Order #{shipment.order_number}",
      count_phrase(length(shipment.shipper_ssccs), "shipper"),
      count_phrase(unit_count, "unit"),
      "Last updated #{eat(shipment.updated_at)}"
    ]
    |> Enum.join(" · ")
  end

  defp status_label("draft"), do: "Draft"
  defp status_label("submitted"), do: "Ready to dispatch"
  defp status_label("approved"), do: "Dispatched"
  defp status_label("rejected"), do: "Rejected"
  defp status_label(status) when is_binary(status), do: Phoenix.Naming.humanize(status)
  defp status_label(_), do: "Unknown"

  defp eat(nil), do: "—"
  defp eat(datetime), do: "#{date_time(datetime)} EAT"

  defp actor(nil), do: "System"
  defp actor(%{name: name}) when is_binary(name) and name != "", do: name
  defp actor(_), do: "System"

  defp packed_at(shipment) do
    shipment.shipper_ssccs
    |> Enum.map(&(&1.completed_at || &1.verified_at))
    |> Enum.reject(&is_nil/1)
    |> Enum.max(fn -> nil end)
  end

  defp unit_count(shipment), do: units_for(shipment.shipper_ssccs)

  defp units_for(shippers) do
    shippers
    |> Enum.map(fn sscc ->
      max(sscc.count_of_trade_items || 0, length(serials(sscc)))
    end)
    |> Enum.sum()
  end

  defp serials(sscc) do
    from_assoc =
      (sscc.serials || [])
      |> Enum.map(& &1.serial)
      |> Enum.reject(&(&1 in [nil, ""]))

    if from_assoc == [], do: sscc.packed_serials || [], else: from_assoc
  end

  defp product_batch(sscc) do
    batches = sscc.batches || []

    products =
      batches
      |> Enum.map(& &1.product)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.name)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    batch_numbers =
      batches
      |> Enum.map(& &1.batch_no)
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.uniq()

    cond do
      products != [] and batch_numbers != [] ->
        "#{Enum.join(products, ", ")} · #{Enum.join(batch_numbers, ", ")}"

      products != [] ->
        Enum.join(products, ", ")

      is_binary(sscc.batch) and sscc.batch != "" ->
        sscc.batch

      true ->
        "—"
    end
  end

  defp formatted_date(nil), do: "—"
  defp formatted_date(%Date{} = date), do: Date.to_string(date)
end
