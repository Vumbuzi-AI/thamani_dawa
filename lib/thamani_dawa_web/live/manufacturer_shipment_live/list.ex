defmodule ThamaniDawaWeb.ManufacturerShipmentLive.List do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Manufacturing
  alias ThamaniDawaWeb.DateRangeFilter

  @tabs [
    {"", "All"},
    {"submitted", "Awaiting review"},
    {"draft", "Drafts"},
    {"approved", "Approved"},
    {"rejected", "Rejected"}
  ]

  def mount(_params, _session, socket) do
    {:ok,
     socket |> assign(:page_title, "Shipments") |> assign(:tabs, @tabs) |> stream(:shipments, [])}
  end

  def handle_params(params, _url, socket) do
    filters = %{
      "status" => valid_status(params["status"]),
      "search" => params["search"] || "",
      "date" => DateRangeFilter.valid_preset(params["date"]),
      "date_from" => params["date_from"] || "",
      "date_to" => params["date_to"] || ""
    }

    {:noreply,
     socket |> assign(:filters, filters) |> assign(:page, page_number(params)) |> load_shipments()}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply,
     socket
     |> load_shipments()
     |> put_flash(:info, "Shipments refreshed.")}
  end

  def handle_event("search", %{"search" => search}, socket),
    do: {:noreply, push_patch(socket, to: filter_path(socket, %{"search" => search}))}

  def handle_event("set_filter", %{"field" => "status", "value" => value}, socket),
    do: {:noreply, push_patch(socket, to: filter_path(socket, %{"status" => value}))}

  def handle_event("set_date_preset", %{"value" => value}, socket) do
    changes = %{"date" => value, "date_from" => "", "date_to" => ""}
    {:noreply, push_patch(socket, to: filter_path(socket, changes))}
  end

  def handle_event("apply_date_range", params, socket) do
    from = params["date_from"] || ""
    to = params["date_to"] || ""
    preset = if from == "" and to == "", do: "", else: "custom"
    changes = %{"date" => preset, "date_from" => from, "date_to" => to}
    {:noreply, push_patch(socket, to: filter_path(socket, changes))}
  end

  defp load_shipments(socket) do
    f = socket.assigns.filters
    organization_id = socket.assigns.current_scope.organization_id
    {date_from, date_to} = DateRangeFilter.resolve(f["date"], f["date_from"], f["date_to"])

    filters = %{
      participant_tier: "manufacturer",
      status: f["status"],
      search: f["search"],
      date_from: date_from,
      date_to: date_to,
      page: socket.assigns.page
    }

    distributor = Distributor.list_shipments(organization_id, filters)

    packed =
      Manufacturing.list_shipments_page(organization_id, %{
        status: f["status"],
        search: f["search"],
        date_from: date_from,
        date_to: date_to,
        page: socket.assigns.page
      })

    rows =
      (Enum.map(distributor.entries, &distributor_row/1) ++
         Enum.map(packed.entries, &packed_row/1))
      |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})

    socket
    |> assign(:page_info, Map.delete(distributor, :entries))
    |> stream(:shipments, rows, reset: true)
  end

  defp distributor_row(shipment) do
    %{
      id: "d-#{shipment.id}",
      order_number: shipment.order_number,
      reference: shipment.reference,
      status: shipment.status,
      origin_company: shipment.origin_company,
      destination_company: shipment.destination_company,
      shipper_count: length(shipment.shippers),
      updated_at: shipment.updated_at,
      path: ~p"/manufacturer/shipments/#{shipment.id}"
    }
  end

  defp packed_row(shipment) do
    %{
      id: "m-#{shipment.id}",
      order_number: shipment.order_number,
      reference: shipment.reference,
      status: shipment.status,
      origin_company: shipment.origin_company,
      destination_company: shipment.destination_company,
      shipper_count: length(shipment.shipper_ssccs),
      updated_at: shipment.updated_at,
      path: ~p"/manufacturer/shipments/packed/#{shipment.id}"
    }
  end

  defp filter_path(socket, changes), do: shipment_path(Map.merge(socket.assigns.filters, changes))
  defp pagination_path(filters), do: shipment_path(filters)

  defp shipment_path(filters),
    do:
      ~p"/manufacturer/shipments?#{filters |> Enum.reject(fn {_k, v} -> v in [nil, ""] end) |> Map.new()}"

  defp valid_status(status) when status in ~w(draft submitted approved rejected), do: status
  defp valid_status(_), do: ""

  defp page_number(params) do
    case Integer.parse(params["page"] || "1") do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/shipments"}
      crumb="Shipments"
    >
      <:search>
        <form id="manufacturer-shipment-search" phx-change="search" phx-submit="search">
          <.td_search
            name="search"
            value={@filters["search"]}
            placeholder="Search order, reference, GLN, customer, GTIN or SSCC"
            shortcut="⌘K"
            phx-debounce="300"
          />
        </form>
      </:search>
      <.td_list_page
        title="Shipments"
        subtitle="Create a shipment from packed SSCCs, then dispatch it when it leaves the plant."
      >
        <:actions>
          <.td_button
            id="refresh-manufacturer-shipments"
            variant="secondary"
            glyph="arrows-clockwise"
            label="Refresh"
            phx-click="refresh"
            phx-disable-with="Refreshing…"
          />
          <.td_button
            id="create-manufacturer-shipment-from-ssccs"
            variant="primary"
            label="New shipment"
            navigate={~p"/manufacturer/shipments/create"}
          />
        </:actions>
        <:filters>
          <.td_filter_menu
            id="manufacturer-shipments"
            field="status"
            label="Status"
            value={@filters["status"]}
            options={@tabs}
          />
          <.td_date_filter
            id="manufacturer-shipments-date"
            label="Date"
            preset={@filters["date"]}
            date_from={@filters["date_from"]}
            date_to={@filters["date_to"]}
          />
          <span class="flex-1"></span>
        </:filters>

        <.td_data_table
          id="manufacturer-shipments"
          rows={@streams.shipments}
          row_id={fn {id, _shipment} -> id end}
        >
          <:col :let={{_id, shipment}} label="Order">
            <.td_pid
              id={"shipment-#{shipment.id}-order"}
              label={shipment.order_number}
              mono
              navigate={shipment.path}
            >
              <:peek>
                <.td_peek
                  kind="Order"
                  title={shipment.order_number}
                  subtitle={shipment.reference}
                  icon="clipboard-text"
                >
                  <:row label="From">{shipment.origin_company}</:row>
                  <:row label="To">{shipment.destination_company}</:row>
                  <:row label="Shippers">{shipment.shipper_count}</:row>
                  <:action>
                    <.td_button label="Review" navigate={shipment.path} />
                  </:action>
                </.td_peek>
              </:peek>
            </.td_pid>
          </:col>
          <:col :let={{_id, shipment}} label="Status">
            <.td_badge
              tone={status_tone(shipment.status)}
              label={Phoenix.Naming.humanize(shipment.status)}
            />
          </:col>
          <:col :let={{_id, shipment}} label="From">{shipment.origin_company}</:col>
          <:col :let={{_id, shipment}} label="To">{shipment.destination_company}</:col>
          <:col :let={{_id, shipment}} label="Last updated">{date_time(shipment.updated_at)}</:col>
          <:action :let={{_id, shipment}}>
            <.td_button
              id={"review-#{shipment.id}"}
              variant="secondary"
              label="Review"
              navigate={shipment.path}
            />
          </:action>
          <:empty>
            <.td_empty
              icon="truck"
              title="No shipments here"
              hint="Nothing matches this status and filter combination yet."
            >
              <:action>
                <.td_button
                  id="empty-create-manufacturer-shipment-from-ssccs"
                  variant="primary"
                  label="New shipment"
                  navigate={~p"/manufacturer/shipments/create"}
                />
              </:action>
            </.td_empty>
          </:empty>
        </.td_data_table>
      </.td_list_page>
      <.pagination page={@page_info} path={pagination_path(@filters)} />
    </Layouts.manufacturer_shell>
    """
  end

  defp status_tone("approved"), do: "success"
  defp status_tone("submitted"), do: "warning"
  defp status_tone("rejected"), do: "danger"
  defp status_tone(_), do: "neutral"
end
