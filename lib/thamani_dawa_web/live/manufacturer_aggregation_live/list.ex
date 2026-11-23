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

  defp filter_path(socket, changes), do: aggregation_path(Map.merge(socket.assigns.filters, changes))
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

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/aggregations"}
      crumb="Aggregations"
    >
      <.td_list_page
        title="Aggregations"
        subtitle="Bind scanned serials to an existing shipper SSCC, then review and approve the pack."
      >
        <:actions>
          <.td_button
            id="new-manufacturer-aggregation"
            variant="primary"
            label="New aggregation"
            navigate={~p"/manufacturer/aggregations/new"}
          />
        </:actions>
        <:filters>
          <form id="manufacturer-aggregation-search" phx-change="search" phx-submit="search">
            <.td_search
              name="search"
              value={@filters["search"]}
              placeholder="Search aggregation reference"
              phx-debounce="300"
            />
          </form>
          <form id="manufacturer-aggregation-filters" phx-change="apply_filters">
            <.td_select
              id="filter-status"
              name="filters[status]"
              label="Status"
              value={@filters["status"]}
              options={Enum.map(@tabs, fn {value, label} -> {label, value} end)}
            />
          </form>
        </:filters>

        <.td_data_table
          id="manufacturer-aggregations"
          rows={@streams.aggregations}
          row_id={fn {id, _aggregation} -> id end}
        >
          <:col :let={{_id, aggregation}} label="Reference">{aggregation.reference}</:col>
          <:col :let={{_id, aggregation}} label="Status">
            <.td_badge
              tone={status_tone(aggregation.status)}
              label={Phoenix.Naming.humanize(aggregation.status)}
            />
          </:col>
          <:col :let={{_id, aggregation}} label="Target SSCC code">
            <span class="td-kv-value is-mono">
              {(aggregation.shipper_sscc && aggregation.shipper_sscc.code) || "—"}
            </span>
          </:col>
          <:col :let={{_id, aggregation}} label="Items count">{aggregation.item_count || 0}</:col>
          <:col :let={{_id, aggregation}} label="Created by">
            {(aggregation.created_by && aggregation.created_by.name) || "—"}
          </:col>
          <:col :let={{_id, aggregation}} label="Updated">{date_time(aggregation.updated_at)}</:col>
          <:action :let={{_id, aggregation}}>
            <.td_button
              variant="secondary"
              label="Review"
              navigate={~p"/manufacturer/aggregations/#{aggregation.id}"}
            />
          </:action>
          <:empty>
            <.td_empty
              title="No aggregations here"
              hint="Nothing matches this status and filter combination yet."
            />
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
