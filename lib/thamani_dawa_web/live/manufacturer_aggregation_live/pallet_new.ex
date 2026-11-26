defmodule ThamaniDawaWeb.ManufacturerAggregationLive.PalletNew do
  @moduledoc """
  Scan shipper SSCCs onto one pallet. A scan is kept, or rejected as a
  duplicate, already on a shipment, empty, or a different destination.
  Creating the pallet mints a GS1 pallet SSCC, records the shipper-to-pallet
  EPCIS aggregation event, and does not open a shipment.
  """
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing
  alias ThamaniDawaWeb.ReturnTo

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Build a pallet")
     |> assign(:accepted, [])
     |> assign(:rejections, [])
     |> assign(:scan_code, "")
     |> assign(:confirming?, false)
     |> assign(:seeded?, false)
     |> assign(:back_path, ~p"/manufacturer/aggregations")
     |> assign(:back_label, "Back to Aggregation")}
  end

  def handle_params(params, _url, socket) do
    back = ReturnTo.path(params, ~p"/manufacturer/aggregations")

    socket =
      socket
      |> assign(:back_path, back)
      |> assign(:back_label, back_label(back, params))
      |> maybe_seed(params["sscc"])

    {:noreply, socket}
  end

  def handle_event("scan", %{"code" => raw}, socket) do
    code = String.trim(raw)

    result =
      Manufacturing.classify_pallet_scan(
        socket.assigns.current_scope.organization_id,
        code,
        accepted_ids: Enum.map(socket.assigns.accepted, & &1.id),
        destination_gln: destination_gln(socket.assigns.accepted)
      )

    socket =
      case result do
        {:ok, shipper} ->
          socket
          |> update(:accepted, &(&1 ++ [shipper]))
          |> assign(:scan_code, "")
          |> drop_rejection(shipper.code)

        {:error, :blank} ->
          assign(socket, :scan_code, "")

        {:error, :unknown, scanned} ->
          socket
          |> assign(:scan_code, "")
          |> put_rejection(scanned, :unknown, "No shipper with that SSCC")

        {:error, reason, shipper, message} ->
          socket
          |> assign(:scan_code, "")
          |> put_rejection(shipper.code, reason, message)
      end

    {:noreply, socket}
  end

  def handle_event("remove", %{"id" => id}, socket) do
    {:noreply,
     update(socket, :accepted, &Enum.reject(&1, fn shipper -> to_string(shipper.id) == id end))}
  end

  def handle_event("dismiss", %{"code" => code}, socket) do
    {:noreply, drop_rejection(socket, code)}
  end

  def handle_event("confirm", _params, socket) do
    {:noreply, assign(socket, :confirming?, socket.assigns.accepted != [])}
  end

  def handle_event("cancel_confirm", _params, socket) do
    {:noreply, assign(socket, :confirming?, false)}
  end

  def handle_event("create", _params, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    ids = Enum.map(socket.assigns.accepted, & &1.id)

    case Manufacturing.create_pallet_from_shippers(organization_id, ids) do
      {:ok, pallet} ->
        {:noreply,
         socket
         |> put_flash(:info, "Pallet SSCC #{pallet.code} created.")
         |> push_navigate(to: ~p"/manufacturer/aggregations/pallets/#{pallet.id}")}

      {:error, :no_shippers} ->
        {:noreply, put_flash(socket, :error, "Scan at least one shipper SSCC.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, create_error(reason))}
    end
  end

  defp maybe_seed(%{assigns: %{seeded?: true}} = socket, _id), do: socket

  defp maybe_seed(socket, id) when id in [nil, ""], do: assign(socket, :seeded?, true)

  defp maybe_seed(socket, id) do
    organization_id = socket.assigns.current_scope.organization_id
    socket = assign(socket, :seeded?, true)

    with {int, ""} <- Integer.parse(to_string(id)),
         %{} = shipper <- Manufacturing.get_shipper_sscc(organization_id, int) do
      case Manufacturing.classify_pallet_scan(organization_id, shipper.code, []) do
        {:ok, shipper} ->
          socket
          |> update(:accepted, &(&1 ++ [shipper]))
          |> assign(:back_label, "Back to shipper #{shipper.code}")

        {:error, reason, shipper, message} ->
          socket
          |> put_rejection(shipper.code, reason, message)
          |> assign(:back_label, "Back to shipper #{shipper.code}")

        _ ->
          socket
      end
    else
      _ -> socket
    end
  end

  defp create_error(:unconfigured),
    do:
      "GS1 isn't set up for your organization. Add your GS1 key in organization settings, then try again."

  defp create_error(reason) when reason in [:unauthorized, :forbidden],
    do: "GS1 rejected your API key. Check it in organization settings, then try again."

  defp create_error(:unavailable),
    do: "We couldn't reach GS1. Your scanned shippers are still here; try again in a moment."

  defp create_error({:invalid, _message}),
    do: "GS1 couldn't accept the pallet details. Check the scanned shippers and try again."

  defp create_error(_reason),
    do: "We couldn't create the pallet label. Try again in a moment."

  defp back_label(path, _params) do
    case path |> URI.parse() |> Map.get(:path) do
      "/manufacturer/aggregations" -> "Back to Aggregation"
      _ -> ReturnTo.label(path, "Back")
    end
  end

  defp destination_gln([%{to_gln: gln} | _]) when gln not in [nil, ""], do: gln
  defp destination_gln(_), do: nil

  defp put_rejection(socket, code, reason, message) do
    rejection = %{code: code, reason: reason, message: message}

    update(socket, :rejections, fn rows ->
      [rejection | Enum.reject(rows, &(&1.code == code))]
    end)
  end

  defp drop_rejection(socket, code) do
    update(socket, :rejections, &Enum.reject(&1, fn row -> row.code == code end))
  end

  defp dom_id(code), do: String.replace(code, ~r/[^A-Za-z0-9]/, "")

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/aggregations"}
      crumb="Build a pallet"
      crumb_parent="Aggregation"
    >
      <.td_back_link id="pallet-back" to={@back_path} label={@back_label} />
      <div class="td-idh">
        <div>
          <h1 class="td-idh-title">Build a pallet</h1>
          <p class="td-idh-sub">
            Scan shipper SSCCs that share a destination. The pallet gets a GS1 SSCC and an EPCIS aggregation event.
          </p>
        </div>
      </div>

      <div class="td-card">
        <form id="pallet-scan-form" phx-submit="scan" class="td-pad">
          <label class="td-field" for="pallet-scan">
            <span class="td-field-label">Scan or type a shipper SSCC</span>
            <input
              id="pallet-scan"
              name="code"
              type="text"
              value={@scan_code}
              autocomplete="off"
              phx-hook="ScanField"
              placeholder="Scan a shipper to add it to this pallet"
              class="td-field-control font-mono"
            />
          </label>
        </form>

        <div :if={@rejections != []} id="pallet-scan-errors" class="td-pad">
          <div
            :for={row <- @rejections}
            id={"pallet-rejection-#{dom_id(row.code)}"}
            class="td-ban is-danger"
          >
            <span>
              <span class="font-mono">{row.code}</span> · {row.message}
            </span>
            <button type="button" phx-click="dismiss" phx-value-code={row.code}>
              Dismiss
            </button>
          </div>
        </div>

        <div :if={@accepted == []} id="pallet-scan-empty" class="td-pad">
          <p class="td-empty-title">No shippers scanned</p>
          <p class="td-note">Create pallet SSCC stays off until the first shipper is accepted.</p>
        </div>

        <table :if={@accepted != []} class="td-rows is-static" id="pallet-scanned">
          <thead>
            <tr>
              <th>Shipper SSCC</th>
              <th>GTIN</th>
              <th>Batch</th>
              <th class="td-num">Units</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={shipper <- @accepted} id={"pallet-scanned-#{shipper.id}"}>
              <td class="font-mono">{shipper.code}</td>
              <td class="font-mono">{shipper.gtin || "—"}</td>
              <td class="font-mono">{shipper.batch || "—"}</td>
              <td class="td-num">{shipper.count_of_trade_items || 0}</td>
              <td>
                <button
                  id={"pallet-remove-#{shipper.id}"}
                  type="button"
                  phx-click="remove"
                  phx-value-id={shipper.id}
                >
                  Remove
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <div class="td-pad" style="display:flex;justify-content:space-between;gap:12px;">
          <.td_button id="pallet-cancel" label="Cancel" navigate={@back_path} />
          <.td_button
            id="open-create-pallet"
            variant="primary"
            label="Create pallet SSCC"
            disabled={@accepted == []}
            phx-click="confirm"
          />
        </div>
      </div>

      <.td_modal
        :if={@confirming?}
        id="create-pallet-modal"
        show
        title="Create pallet SSCC"
        subtitle={"#{length(@accepted)} shippers · GS1 pallet SSCC"}
        on_cancel={JS.push("cancel_confirm")}
      >
        <:body>
          <p class="td-note">
            This mints the pallet SSCC and reports the shippers inside it to EPCIS. It does not create a shipment.
          </p>
          <ul id="create-pallet-preview">
            <li :for={shipper <- @accepted} class="font-mono">{shipper.code}</li>
          </ul>
        </:body>
        <:footer>
          <.td_button label="Cancel" phx-click="cancel_confirm" />
          <.td_button
            id="create-pallet-sscc"
            variant="primary"
            label="Create pallet SSCC"
            phx-click="create"
            phx-disable-with="Creating…"
          />
        </:footer>
      </.td_modal>
    </Layouts.manufacturer_shell>
    """
  end
end
