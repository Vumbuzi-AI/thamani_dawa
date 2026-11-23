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

  defp active_filter_count(filters),
    do: Enum.count(["status", "date_from", "date_to"], &(filters[&1] not in [nil, ""]))

  defp unit_count(shipment),
    do: shipment.shippers |> Enum.map(&length(&1.items)) |> Enum.sum()

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/shipments"}
    >
      <.header icon="hero-truck">
        Shipments
        <:subtitle>
          Create shipments, then review packed SSCCs and approve them for dispatch.
        </:subtitle>
        <:actions>
          <.button
            id="new-manufacturer-shipment"
            variant="primary"
            navigate={~p"/manufacturer/shipments/new"}
          ><.icon name="hero-plus" class="size-4" /> New shipment</.button>
        </:actions>
        <:toolbar>
          <form id="manufacturer-shipment-search" phx-change="search" phx-submit="search">
            <.search_input
              name="search"
              value={@filters["search"]}
              placeholder="Search order, reference, GLN, customer, GTIN or SSCC"
            />
          </form>
          <div class="flex flex-wrap items-center gap-2">
            <.filter_drawer
              id="manufacturer-shipment-filters"
              title="Filter shipments"
              apply_event="apply_filters"
              active_count={active_filter_count(@filters)}
            >
              <:group label="Status">
                <.input
                  type="select"
                  id="filter-status"
                  name="filters[status]"
                  value={@filters["status"]}
                  options={Enum.map(@tabs, fn {value, label} -> {label, value} end)}
                />
              </:group>
              <:group label="Created between">
                <div class="grid grid-cols-2 gap-2">
                  <.input
                    type="date"
                    id="filter-date-from"
                    name="filters[date_from]"
                    value={@filters["date_from"]}
                  /><.input
                    type="date"
                    id="filter-date-to"
                    name="filters[date_to]"
                    value={@filters["date_to"]}
                  />
                </div>
              </:group>
              <:chip
                :if={@filters["status"] != ""}
                label={"Status: #{Phoenix.Naming.humanize(@filters["status"])}"}
                clear={JS.push("clear_filter", value: %{filter: "status"})}
              />
              <:chip
                :if={@filters["date_from"] != ""}
                label={"From #{@filters["date_from"]}"}
                clear={JS.push("clear_filter", value: %{filter: "date_from"})}
              />
              <:chip
                :if={@filters["date_to"] != ""}
                label={"To #{@filters["date_to"]}"}
                clear={JS.push("clear_filter", value: %{filter: "date_to"})}
              />
            </.filter_drawer>
          </div>
        </:toolbar>
      </.header>

      <.table
        id="manufacturer-shipments"
        rows={@streams.shipments}
        row_click={fn {_id, shipment} -> JS.navigate(~p"/manufacturer/shipments/#{shipment.id}") end}
      >
        <:col :let={{_id, shipment}} label="Order">
          <div class="min-w-0">
            <p class="font-medium text-thamani-forest">{shipment.order_number}</p><p class="font-mono text-xs text-thamani-pewter">
              {shipment.reference}
            </p>
          </div>
        </:col>
        <:col :let={{_id, shipment}} label="Status" mobile="aside">
          <.shipment_status_badge status={shipment.status} />
        </:col>
        <:col :let={{_id, shipment}} label="From">
          <span class="text-sm">{shipment.origin_company}</span>
        </:col>
        <:col :let={{_id, shipment}} label="To">
          <span class="text-sm">{shipment.destination_company}</span>
        </:col>
        <:col :let={{_id, shipment}} label="Shippers / units">
          {length(shipment.shippers)} / {unit_count(shipment)}
        </:col>
        <:col :let={{_id, shipment}} label="Mobile user" tablet="hidden">
          {(shipment.assigned_to && shipment.assigned_to.name) || "Unclaimed"}
        </:col>
        <:col :let={{_id, shipment}} label="Updated" mobile="hidden">
          <span class="text-xs text-thamani-pewter">{date_time(shipment.updated_at)}</span>
        </:col>
        <:empty_state>
          <.blank_state icon="hero-truck" title="No shipments here">
            Nothing matches this status and filter combination yet.
          </.blank_state>
        </:empty_state>
      </.table>
      <.pagination page={@page_info} path={pagination_path(@filters)} />
    </Layouts.manufacturer_shell>
    """
  end
end
