defmodule ThamaniDawaWeb.ManufacturerShipmentLive.Review do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Distributor

  def mount(%{"id" => id}, _session, socket), do: {:ok, load(socket, id)}

  def handle_event("approve", _params, socket) do
    scope = socket.assigns.current_scope

    case Distributor.approve_shipment(
           scope.organization_id,
           scope.user,
           socket.assigns.shipment.id
         ) do
      {:ok, shipment} ->
        shipment = Distributor.get_shipment!(scope.organization_id, shipment.id, "manufacturer")

        {:noreply,
         socket
         |> assign_shipment(shipment)
         |> put_flash(:info, "Shipment dispatched.")}

      {:error, {:invalid_state, "approved"}} ->
        {:noreply, put_flash(socket, :info, "This shipment has already been dispatched.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Shipment could not be dispatched.")}
    end
  end

  defp load(socket, id) do
    shipment =
      Distributor.get_shipment!(
        socket.assigns.current_scope.organization_id,
        id,
        "manufacturer"
      )

    socket
    |> assign(:page_title, shipment.reference)
    |> assign_shipment(shipment)
  end

  defp assign_shipment(socket, shipment) do
    socket
    |> assign(:shipment, shipment)
    |> assign(:unit_count, shipment.shippers |> Enum.map(&length(&1.items)) |> Enum.sum())
  end

  defp count_phrase(1, noun), do: "1 #{noun}"
  defp count_phrase(count, noun), do: "#{count} #{noun}s"

  defp status_label("draft"), do: "Draft"
  defp status_label("submitted"), do: "Ready to dispatch"
  defp status_label("approved"), do: "Dispatched"
  defp status_label("rejected"), do: "Rejected"
  defp status_label(status), do: Phoenix.Naming.humanize(status || "unknown")

  defp status_tone("draft"), do: "neutral"
  defp status_tone("submitted"), do: "info"
  defp status_tone("approved"), do: "success"
  defp status_tone("rejected"), do: "danger"
  defp status_tone(_), do: "neutral"

  defp header_sub(shipment, unit_count) do
    line =
      [
        "Order #{shipment.order_number}",
        count_phrase(length(shipment.shippers), "shipper"),
        count_phrase(unit_count, "unit")
      ]
      |> Enum.join(" · ")

    case shipment.destination_company do
      company when is_binary(company) and company != "" -> "#{line} to #{company}"
      _ -> line
    end
  end

  defp eat(nil), do: "—"
  defp eat(datetime), do: "#{date_time(datetime)} EAT"

  defp dispatched_at(%{status: "approved", approved_at: at}), do: eat(at)
  defp dispatched_at(_shipment), do: "Not yet"

  defp person(nil), do: "System"
  defp person(%{name: name}) when is_binary(name) and name != "", do: name
  defp person(_), do: "System"

  defp contents(shipper) do
    units = count_phrase(length(shipper.items), "unit")

    case shipper.product_name do
      name when is_binary(name) and name != "" -> "#{name} · #{units}"
      _ -> units
    end
  end

  def render(%{live_action: :packing_list} = assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/shipments"}
      crumb_parent="Shipments"
      crumb="Packing list"
    >
      <div class="td-recipe td-list-page td-detail-page">
        <.td_back_link
          id="packing-list-back"
          to={~p"/manufacturer/shipments/#{@shipment.id}"}
          label="Back to shipment"
        />
        <header class="td-idh">
          <div class="td-idh-text">
            <h1 class="td-idh-title"><span>Packing list</span></h1>
            <p class="td-idh-sub">{@shipment.reference} · Order {@shipment.order_number}</p>
          </div>
        </header>
        <div class="td-pad td-stack">
          <div class="td-card">
            <dl class="td-kv-grid is-pad is-4">
              <.td_key_value label="Shipment" value={@shipment.reference} mono />
              <.td_key_value label="Order" value={@shipment.order_number} />
              <.td_key_value label="From" value={@shipment.origin_company || "—"} />
              <.td_key_value label="To" value={@shipment.destination_company || "—"} />
            </dl>
          </div>
          <div class="td-card">
            <.td_card_header title="Shippers" subtitle="Lines on this packing list" />
            <div :if={@shipment.shippers == []} class="td-pad">
              <.td_empty
                title="Nothing packed yet"
                hint="A mobile user scans units into shippers before this list has lines."
              />
            </div>
            <table :if={@shipment.shippers != []} class="td-rows" id="manufacturer-packing-list">
              <thead>
                <tr>
                  <th>Shipper</th>
                  <th>SSCC</th>
                  <th>Product</th>
                  <th>Batch</th>
                  <th class="is-num">Units</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={shipper <- @shipment.shippers} id={"packing-shipper-#{shipper.id}"}>
                  <td>{shipper.name || "Shipper #{shipper.sequence}"}</td>
                  <td><span class="td-mono">{shipper.sscc || "—"}</span></td>
                  <td>{shipper.product_name || "Packed trade items"}</td>
                  <td><span class="td-mono">{shipper.batch || "Mixed"}</span></td>
                  <td class="is-num">{length(shipper.items)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </Layouts.manufacturer_shell>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/shipments"}
      crumb_parent="Shipments"
      crumb={@shipment.reference}
    >
      <:tools>
        <.td_button
          :if={@shipment.status == "submitted"}
          id="approve-manufacturer-shipment"
          variant="primary"
          glyph="truck"
          label="Dispatch shipment"
          phx-click="approve"
        />
      </:tools>

      <div class="no-print td-recipe td-list-page td-detail-page" id="manufacturer-shipment-detail">
        <.td_back_link
          id="manufacturer-shipment-back"
          to={~p"/manufacturer/shipments"}
          label="Back to Shipments"
        />

        <header class="td-idh">
          <div class="td-idh-text">
            <h1 class="td-idh-title">
              <span>{@shipment.reference}</span>
              <.td_badge tone={status_tone(@shipment.status)} label={status_label(@shipment.status)} />
            </h1>
            <p class="td-idh-sub">{header_sub(@shipment, @unit_count)}</p>
          </div>
          <div class="td-idh-actions">
            <.td_button
              id="manufacturer-packing-list"
              glyph="list-checks"
              label="Packing list"
              navigate={~p"/manufacturer/shipments/#{@shipment.id}/packing-list"}
            />
          </div>
        </header>

        <div class="td-pad td-stack">
          <div :if={@shipment.status == "draft"} id="manufacturer-draft-note" class="td-ban is-info">
            <.td_icon name="info" />
            <span>
              Nothing is packed yet. A mobile user finds this shipment by order {@shipment.order_number} and scans units into shippers.
            </span>
          </div>

          <div :if={@shipment.status == "rejected"} id="manufacturer-rejection" class="td-ban is-danger">
            <.td_icon name="x-circle" />
            <span>
              <b>Rejected.</b>
              {@shipment.rejection_reason}
            </span>
          </div>

          <div class="td-card">
            <dl class="td-kv-grid is-pad is-4">
              <.td_key_value label="Shipment" value={@shipment.reference} mono />
              <.td_key_value label="Order" value={@shipment.order_number} />
              <.td_key_value label="Shippers" value={length(@shipment.shippers)} />
              <.td_key_value label="Units" value={@unit_count} />
              <.td_key_value label="Created" value={eat(@shipment.inserted_at)} />
              <.td_key_value label="Dispatched" value={dispatched_at(@shipment)} />
            </dl>
          </div>

          <div class="grid gap-4 md:grid-cols-2">
            <section class="td-card td-party-card">
              <span class="td-k"><.td_icon name="factory" /> From</span>
              <span class="td-v">{@shipment.origin_company || "—"}</span>
              <span class="td-mono">GLN {@shipment.origin_gln || "—"}</span>
              <span :if={@shipment.origin_address} class="td-a">{@shipment.origin_address}</span>
            </section>
            <section class="td-card td-party-card">
              <span class="td-k"><.td_icon name="warehouse" /> To</span>
              <span class="td-v">{@shipment.destination_company || "—"}</span>
              <span class="td-mono">GLN {@shipment.destination_gln || "—"}</span>
              <span :if={@shipment.destination_address} class="td-a">{@shipment.destination_address}</span>
            </section>
          </div>

          <div class="td-detail-row">
            <div class="td-card" id="manufacturer-shippers">
              <.td_card_header title="Contents" subtitle="Shippers on this shipment" />
              <div :if={@shipment.shippers == []} class="td-pad">
                <.td_empty
                  title="Nothing packed yet"
                  hint={"A mobile user finds this shipment by order #{@shipment.order_number} and scans units into shippers."}
                />
              </div>
              <table :if={@shipment.shippers != []} class="td-rows" id="manufacturer-contents">
                <thead>
                  <tr>
                    <th>SSCC</th>
                    <th>Level</th>
                    <th>Contents</th>
                    <th>Batch</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={shipper <- @shipment.shippers} id={"shipper-#{shipper.id}"}>
                    <td><span class="td-mono">{shipper.sscc || "Not issued yet"}</span></td>
                    <td>Shipper</td>
                    <td>{contents(shipper)}</td>
                    <td><span class="td-mono">{shipper.batch || "Mixed"}</span></td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div class="td-card" id="manufacturer-shipment-activity">
              <.td_card_header title="Activity" subtitle="Times in EAT" />
              <ol class="td-list">
                <li class="td-li">
                  <.td_orb seed={person(@shipment.created_by)} size={24} />
                  <div class="td-li-g">
                    <b>Shipment created</b>
                    <span>{person(@shipment.created_by)} · {eat(@shipment.inserted_at)}</span>
                  </div>
                </li>
                <li :if={@shipment.status in ["submitted", "approved"]} class="td-li">
                  <.td_orb seed="packer" size={24} />
                  <div class="td-li-g">
                    <b>{count_phrase(length(@shipment.shippers), "shipper")} packed</b>
                    <span>{eat(@shipment.submitted_at)}</span>
                  </div>
                </li>
                <li :if={@shipment.status == "approved"} class="td-li">
                  <.td_orb seed={person(@shipment.approved_by)} size={24} />
                  <div class="td-li-g">
                    <b>Dispatched</b>
                    <span>{person(@shipment.approved_by)} · {eat(@shipment.approved_at)}</span>
                  </div>
                </li>
                <li :if={@shipment.status == "rejected"} class="td-li">
                  <.td_orb seed="rejected" size={24} />
                  <div class="td-li-g">
                    <b>Rejected</b>
                    <span>{eat(@shipment.rejected_at)}</span>
                  </div>
                </li>
              </ol>
            </div>
          </div>
        </div>
      </div>
    </Layouts.manufacturer_shell>
    """
  end
end
