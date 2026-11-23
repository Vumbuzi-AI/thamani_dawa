defmodule ThamaniDawaWeb.ManufacturerShipmentLive.List do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Distributor

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
      "date_from" => params["date_from"] || "",
      "date_to" => params["date_to"] || ""
    }

    {:noreply,
     socket |> assign(:filters, filters) |> assign(:page, page_number(params)) |> load_shipments()}
  end

  def handle_event("search", %{"search" => search}, socket),
    do: {:noreply, push_patch(socket, to: filter_path(socket, %{"search" => search}))}

  def handle_event("apply_filters", %{"filters" => filters}, socket),
    do:
      {:noreply,
       push_patch(socket,
         to: filter_path(socket, Map.take(filters, ["status", "date_from", "date_to"]))
       )}

  def handle_event("clear_filter", %{"filter" => filter}, socket)
      when filter in ["status", "date_from", "date_to"],
      do: {:noreply, push_patch(socket, to: filter_path(socket, %{filter => ""}))}

  defp load_shipments(socket) do
    f = socket.assigns.filters

    result =
      Distributor.list_shipments(socket.assigns.current_scope.organization_id, %{
        participant_tier: "manufacturer",
        status: f["status"],
        search: f["search"],
        date_from: parse_date(f["date_from"]),
        date_to: parse_date(f["date_to"]),
        page: socket.assigns.page
      })

    socket
    |> assign(:page_info, Map.delete(result, :entries))
    |> stream(:shipments, result.entries, reset: true)
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

  defp parse_date(value) do
    case Date.from_iso8601(value || "") do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp unit_count(shipment),
    do: shipment.shippers |> Enum.map(&length(&1.items)) |> Enum.sum()

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/shipments"}
      crumb="Shipments"
    >
      <.td_list_page
        title="Shipments"
        subtitle="Create shipments, then review packed SSCCs and approve them for dispatch."
      >
        <:actions>
          <.td_button
            id="new-manufacturer-shipment"
            variant="primary"
            label="New shipment"
            navigate={~p"/manufacturer/shipments/new"}
          />
        </:actions>
        <:filters>
          <form id="manufacturer-shipment-search" phx-change="search" phx-submit="search">
            <.td_search
              name="search"
              value={@filters["search"]}
              placeholder="Search order, reference, GLN, customer, GTIN or SSCC"
              phx-debounce="300"
            />
          </form>
          <form id="manufacturer-shipment-filters" phx-change="apply_filters" class="td-filter-row">
            <.td_select
              id="filter-status"
              name="filters[status]"
              label="Status"
              value={@filters["status"]}
              options={Enum.map(@tabs, fn {value, label} -> {label, value} end)}
            />
            <.date_picker
              id="filter-date-from"
              name="filters[date_from]"
              label="From"
              value={@filters["date_from"]}
            />
            <.date_picker
              id="filter-date-to"
              name="filters[date_to]"
              label="To"
              value={@filters["date_to"]}
            />
          </form>
        </:filters>

        <.td_data_table
          id="manufacturer-shipments"
          rows={@streams.shipments}
          row_id={fn {id, _shipment} -> id end}
        >
          <:col :let={{_id, shipment}} label="Order">
            <.td_key_value label={shipment.order_number} value={shipment.reference} mono />
          </:col>
          <:col :let={{_id, shipment}} label="Status">
            <.td_badge tone={status_tone(shipment.status)} label={Phoenix.Naming.humanize(shipment.status)} />
          </:col>
          <:col :let={{_id, shipment}} label="From">{shipment.origin_company}</:col>
          <:col :let={{_id, shipment}} label="To">{shipment.destination_company}</:col>
          <:col :let={{_id, shipment}} label="Shippers / units">
            {length(shipment.shippers)} / {unit_count(shipment)}
          </:col>
          <:col :let={{_id, shipment}} label="Mobile user">
            {(shipment.assigned_to && shipment.assigned_to.name) || "Unclaimed"}
          </:col>
          <:col :let={{_id, shipment}} label="Updated">{date_time(shipment.updated_at)}</:col>
          <:action :let={{_id, shipment}}>
            <.td_button
              variant="secondary"
              label="Review"
              navigate={~p"/manufacturer/shipments/#{shipment.id}"}
            />
          </:action>
          <:empty>
            <.td_empty title="No shipments here" hint="Nothing matches this status and filter combination yet." />
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
