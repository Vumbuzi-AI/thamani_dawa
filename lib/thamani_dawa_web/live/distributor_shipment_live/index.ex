defmodule ThamaniDawaWeb.DistributorShipmentLive.Index do
  @moduledoc """
  Distributor shipment list: status tabs (submitted first), free-text
  search, mobile-user and date filters, pagination, and live refresh when
  shipments change on the mobile app or elsewhere in the portal.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Distributor

  on_mount {ThamaniDawaWeb.DistributorAccess, :require_serialisation_plan}

  @tabs [
    {"submitted", "Awaiting review"},
    {"draft", "Drafts"},
    {"approved", "Approved"},
    {"rejected", "Rejected"}
  ]

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    if connected?(socket), do: Distributor.subscribe(organization_id)

    {:ok,
     socket
     |> assign(:page_title, "Shipments")
     |> assign(:tabs, @tabs)
     |> assign(:mobile_users, Distributor.list_mobile_users(organization_id))
     |> stream(:shipments, [])}
  end

  def handle_params(params, _url, socket) do
    filters = %{
      "status" => valid_status(params["status"]),
      "search" => params["search"] || "",
      "mobile_user_id" => params["mobile_user_id"] || "",
      "date_from" => params["date_from"] || "",
      "date_to" => params["date_to"] || ""
    }

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:page, page_number(params))
     |> load_shipments()}
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, push_patch(socket, to: path(socket, %{"search" => search}))}
  end

  def handle_event("apply_filters", %{"filters" => filters}, socket) do
    changes = Map.take(filters, ["mobile_user_id", "date_from", "date_to"])
    {:noreply, push_patch(socket, to: path(socket, changes))}
  end

  def handle_event("clear_filters", _params, socket) do
    changes = %{"mobile_user_id" => "", "date_from" => "", "date_to" => ""}
    {:noreply, push_patch(socket, to: path(socket, changes))}
  end

  def handle_event("clear_filter", %{"filter" => filter}, socket)
      when filter in ["mobile_user_id", "date_from", "date_to"] do
    {:noreply, push_patch(socket, to: path(socket, %{filter => ""}))}
  end

  def handle_info({:distributor_shipment, _event, _shipment_id}, socket) do
    {:noreply, load_shipments(socket)}
  end

  defp load_shipments(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    filters = socket.assigns.filters

    result =
      Distributor.list_shipments(organization_id, %{
        status: filters["status"],
        search: filters["search"],
        mobile_user_id: parse_id(filters["mobile_user_id"]),
        date_from: parse_date(filters["date_from"]),
        date_to: parse_date(filters["date_to"]),
        page: socket.assigns.page
      })

    socket
    |> assign(:page_info, Map.delete(result, :entries))
    |> assign(:status_counts, Distributor.status_counts(organization_id))
    |> stream(:shipments, result.entries, reset: true)
  end

  defp path(socket, changes) do
    query =
      socket.assigns.filters
      |> Map.merge(changes)
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    ~p"/distributor/shipments?#{query}"
  end

  defp tab_path(filters, status) do
    query =
      filters
      |> Map.put("status", status)
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    ~p"/distributor/shipments?#{query}"
  end

  defp pagination_path(filters) do
    query =
      filters
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    ~p"/distributor/shipments?#{query}"
  end

  defp valid_status(status) when status in ["draft", "submitted", "approved", "rejected"],
    do: status

  defp valid_status(_status), do: "submitted"

  defp page_number(params) do
    case Integer.parse(params["page"] || "1") do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp parse_id(value) do
    case Integer.parse(value || "") do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp parse_date(value) do
    case Date.from_iso8601(value || "") do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp active_filter_count(filters),
    do: Enum.count(["mobile_user_id", "date_from", "date_to"], &(filters[&1] not in [nil, ""]))

  defp mobile_user_name(mobile_users, id) do
    case Enum.find(mobile_users, &(Integer.to_string(&1.id) == id)) do
      nil -> "Unknown"
      mobile_user -> mobile_user.name
    end
  end

  defp unit_count(shipment),
    do: shipment.shippers |> Enum.map(&length(&1.items)) |> Enum.sum()

  defp holder(%{status: "draft", assigned_to: nil}), do: "Unclaimed"
  defp holder(%{status: "draft", assigned_to: mobile_user}), do: mobile_user.name
  defp holder(%{submitted_by: nil, assigned_to: nil}), do: "—"
  defp holder(%{submitted_by: nil, assigned_to: mobile_user}), do: mobile_user.name
  defp holder(%{submitted_by: mobile_user}), do: mobile_user.name

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/shipments"}
    >
      <.header icon="hero-truck">
        Shipments
        <:subtitle>
          Create shipments, then review what your mobile team packed and approve to issue SSCCs.
        </:subtitle>
        <:actions>
          <.button
            id="new-distributor-shipment"
            variant="primary"
            navigate={~p"/distributor/shipments/new"}
          >
            <.icon name="hero-plus" class="size-4" /> New shipment
          </.button>
        </:actions>
        <:toolbar>
          <form id="distributor-shipment-search" phx-change="search" phx-submit="search">
            <.search_input
              name="search"
              value={@filters["search"]}
              placeholder="Search order, reference, GLN, customer, GTIN, batch, serial or SSCC"
            />
          </form>
          <div class="flex flex-wrap items-center gap-2">
            <.filter_drawer
              id="distributor-shipment-filters"
              title="Filter shipments"
              apply_event="apply_filters"
              active_count={active_filter_count(@filters)}
            >
              <:group label="Mobile user">
                <.input
                  type="select"
                  id="filter-mobile-user"
                  name="filters[mobile_user_id]"
                  value={@filters["mobile_user_id"]}
                  prompt="Anyone"
                  options={Enum.map(@mobile_users, &{&1.name, &1.id})}
                />
              </:group>
              <:group label="Created between">
                <div class="grid grid-cols-2 gap-2">
                  <.input
                    type="date"
                    id="filter-date-from"
                    name="filters[date_from]"
                    value={@filters["date_from"]}
                  />
                  <.input
                    type="date"
                    id="filter-date-to"
                    name="filters[date_to]"
                    value={@filters["date_to"]}
                  />
                </div>
              </:group>
              <:chip
                :if={@filters["mobile_user_id"] != ""}
                label={"Mobile user: #{mobile_user_name(@mobile_users, @filters["mobile_user_id"])}"}
                clear={JS.push("clear_filter", value: %{filter: "mobile_user_id"})}
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

      <nav
        id="distributor-shipment-tabs"
        class="mb-4 flex gap-1 overflow-x-auto rounded-xl border border-thamani-stone bg-white p-1"
        aria-label="Shipment status"
      >
        <.link
          :for={{status, label} <- @tabs}
          id={"shipment-tab-#{status}"}
          patch={tab_path(@filters, status)}
          class={[
            "flex flex-1 items-center justify-center gap-2 whitespace-nowrap rounded-lg px-3 py-2 text-sm font-medium transition-colors duration-150",
            if(@filters["status"] == status,
              do: "bg-thamani-forest text-white shadow-sm",
              else: "text-thamani-pewter hover:bg-thamani-canvas hover:text-thamani-forest"
            )
          ]}
          aria-current={@filters["status"] == status && "page"}
        >
          {label}
          <span class={[
            "rounded-full px-2 py-0.5 text-xs font-semibold",
            if(@filters["status"] == status,
              do: "bg-white/20 text-white",
              else: "bg-thamani-stone text-thamani-forest"
            )
          ]}>
            {@status_counts[status]}
          </span>
        </.link>
      </nav>

      <.table
        id="distributor-shipments"
        rows={@streams.shipments}
        row_click={fn {_id, shipment} -> JS.navigate(~p"/distributor/shipments/#{shipment.id}") end}
      >
        <:col :let={{_id, shipment}} label="Order">
          <div class="min-w-0">
            <p class="font-medium text-thamani-forest">{shipment.order_number}</p>
            <p class="font-mono text-xs text-thamani-pewter">{shipment.reference}</p>
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
          {holder(shipment)}
        </:col>
        <:col :let={{_id, shipment}} label="Updated" mobile="hidden">
          <span class="text-xs text-thamani-pewter">{date_time(shipment.updated_at)}</span>
        </:col>
        <:empty_state>
          <.blank_state icon="hero-truck" title="No shipments here">
            <%= if @filters["status"] == "draft" do %>
              Create a shipment so your mobile team can find it by order number and start packing.
            <% else %>
              Nothing matches this status and filter combination yet.
            <% end %>
          </.blank_state>
        </:empty_state>
      </.table>
      <.pagination page={@page_info} path={pagination_path(@filters)} />
    </Layouts.distributor_shell>
    """
  end
end
