defmodule ThamaniDawaWeb.ManufacturerAggregationLive.List do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing

  @tabs [
    {"", "All"},
    {"submitted", "Awaiting review"},
    {"draft", "Drafts"},
    {"approved", "Approved"},
    {"rejected", "Rejected"}
  ]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Aggregations")
     |> assign(:tabs, @tabs)
     |> stream(:aggregations, [])}
  end

  def handle_params(params, _url, socket) do
    filters = %{
      "status" => valid_status(params["status"]),
      "search" => params["search"] || ""
    }

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:page, page_number(params))
     |> load_aggregations()}
  end

  def handle_event("search", %{"search" => search}, socket),
    do: {:noreply, push_patch(socket, to: filter_path(socket, %{"search" => search}))}

  def handle_event("apply_filters", %{"filters" => filters}, socket),
    do:
      {:noreply,
       push_patch(socket,
         to: filter_path(socket, Map.take(filters, ["status"]))
       )}

  def handle_event("clear_filter", %{"filter" => "status"}, socket),
    do: {:noreply, push_patch(socket, to: filter_path(socket, %{"status" => ""}))}

  defp load_aggregations(socket) do
    f = socket.assigns.filters

    result =
      Manufacturing.list_aggregations(socket.assigns.current_scope.organization_id, %{
        status: f["status"],
        search: f["search"],
        page: socket.assigns.page
      })

    socket
    |> assign(:page_info, Map.delete(result, :entries))
    |> stream(:aggregations, result.entries, reset: true)
  end

  defp filter_path(socket, changes),
    do: aggregation_path(Map.merge(socket.assigns.filters, changes))

  defp pagination_path(filters), do: aggregation_path(filters)

  defp aggregation_path(filters),
    do:
      ~p"/manufacturer/aggregations?#{filters |> Enum.reject(fn {_k, v} -> v in [nil, ""] end) |> Map.new()}"

  defp valid_status(status) when status in ~w(draft submitted approved rejected), do: status
  defp valid_status(_), do: ""

  defp page_number(params) do
    case Integer.parse(params["page"] || "1") do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp active_filter_count(filters),
    do: Enum.count(["status"], &(filters[&1] not in [nil, ""]))

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/aggregations"}
    >
      <.header icon="hero-squares-plus">
        Aggregations
        <:subtitle>
          Bind scanned serials to an existing shipper SSCC, then review and approve the pack.
        </:subtitle>
        <:actions>
          <.button
            id="new-manufacturer-aggregation"
            variant="primary"
            navigate={~p"/manufacturer/aggregations/new"}
          ><.icon name="hero-plus" class="size-4" /> New aggregation</.button>
        </:actions>
        <:toolbar>
          <form id="manufacturer-aggregation-search" phx-change="search" phx-submit="search">
            <.search_input
              name="search"
              value={@filters["search"]}
              placeholder="Search aggregation reference"
            />
          </form>
          <div class="flex flex-wrap items-center gap-2">
            <.filter_drawer
              id="manufacturer-aggregation-filters"
              title="Filter aggregations"
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
              <:chip
                :if={@filters["status"] != ""}
                label={"Status: #{Phoenix.Naming.humanize(@filters["status"])}"}
                clear={JS.push("clear_filter", value: %{filter: "status"})}
              />
            </.filter_drawer>
          </div>
        </:toolbar>
      </.header>

      <.table
        id="manufacturer-aggregations"
        rows={@streams.aggregations}
        row_click={
          fn {_id, aggregation} ->
            JS.navigate(~p"/manufacturer/aggregations/#{aggregation.id}")
          end
        }
      >
        <:col :let={{_id, aggregation}} label="Reference">
          <p class="font-medium text-thamani-forest">{aggregation.reference}</p>
        </:col>
        <:col :let={{_id, aggregation}} label="Status" mobile="aside">
          <.aggregation_status_badge status={aggregation.status} />
        </:col>
        <:col :let={{_id, aggregation}} label="Target SSCC code">
          <span class="font-mono text-xs text-thamani-pewter">
            {(aggregation.shipper_sscc && aggregation.shipper_sscc.code) || "—"}
          </span>
        </:col>
        <:col :let={{_id, aggregation}} label="Items count">
          {aggregation.item_count || 0}
        </:col>
        <:col :let={{_id, aggregation}} label="Created by">
          {(aggregation.created_by && aggregation.created_by.name) || "—"}
        </:col>
        <:col :let={{_id, aggregation}} label="Updated" mobile="hidden">
          <span class="text-xs text-thamani-pewter">{date_time(aggregation.updated_at)}</span>
        </:col>
        <:empty_state>
          <.blank_state icon="hero-squares-plus" title="No aggregations here">
            Nothing matches this status and filter combination yet.
          </.blank_state>
        </:empty_state>
      </.table>
      <.pagination page={@page_info} path={pagination_path(@filters)} />
    </Layouts.manufacturer_shell>
    """
  end
end
