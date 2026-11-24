defmodule ThamaniDawaWeb.PlatformAuditLive do
  @moduledoc """
  Platform audit trail: filterable, paginated activity across every
  organization, with totals by action. Patient-identifying values are
  never shown — only table/record/actor/organization metadata.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.PlatformMonitoring

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Audit activity")
     |> assign(:stats, PlatformMonitoring.audit_activity_stats())
     |> assign(:tables, PlatformMonitoring.list_audited_tables())
     |> assign(:actors, PlatformMonitoring.list_audit_actors())}
  end

  def handle_params(params, _url, socket) do
    filters = %{
      "table" => params["table"] || "",
      "user" => params["user"] || "",
      "action" => params["action"] || "",
      "search" => params["search"] || ""
    }

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:page, page_number(params))
     |> load_audit_logs()}
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, push_patch(socket, to: filter_path(socket, %{"search" => search}))}
  end

  def handle_event("set_filter", %{"field" => field, "value" => value}, socket)
      when field in ["table", "user", "action"] do
    {:noreply, push_patch(socket, to: filter_path(socket, %{field => value}))}
  end

  def handle_event("clear_filters", _params, socket) do
    changes = %{"table" => "", "user" => "", "action" => "", "search" => ""}
    {:noreply, push_patch(socket, to: filter_path(socket, changes))}
  end

  def handle_event("clear_filter", %{"filter" => filter}, socket)
      when filter in ["table", "user", "action", "search"] do
    {:noreply, push_patch(socket, to: filter_path(socket, %{filter => ""}))}
  end

  defp load_audit_logs(socket) do
    filters = socket.assigns.filters

    result =
      PlatformMonitoring.list_audit_activity(
        table_name: blank_to_nil(filters["table"]),
        user_id: parse_id(filters["user"]),
        action: blank_to_nil(filters["action"]),
        search: blank_to_nil(filters["search"]),
        page: socket.assigns.page
      )

    assign(socket, :page_info, result)
  end

  defp filter_path(socket, changes) do
    query =
      socket.assigns.filters
      |> Map.merge(changes)
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    ~p"/platform/audit?#{query}"
  end

  defp pagination_path(filters) do
    query = filters |> Enum.reject(fn {_key, value} -> value in [nil, ""] end) |> Map.new()
    ~p"/platform/audit?#{query}"
  end

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

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp active_filter_count(filters),
    do: Enum.count(["table", "user", "action"], &(filters[&1] not in [nil, ""]))

  defp organization_name(%{organization: %{name: name}}), do: name
  defp organization_name(_log), do: "Platform"

  defp actor_display(%{user: %{name: name}}), do: name
  defp actor_display(_log), do: "System"

  defp action_icon("insert"), do: "hero-plus-circle"
  defp action_icon("update"), do: "hero-pencil-square"
  defp action_icon("delete"), do: "hero-trash"
  defp action_icon(_action), do: "hero-clock"

  defp action_classes("insert"), do: "bg-emerald-100 text-emerald-800"
  defp action_classes("update"), do: "bg-sky-100 text-sky-800"
  defp action_classes("delete"), do: "bg-rose-100 text-rose-800"
  defp action_classes(_action), do: "bg-thamani-stone text-thamani-pewter"

  defp action_label(action), do: Phoenix.Naming.humanize(action)

  defp format_table_name(table_name), do: table_name |> Phoenix.Naming.humanize()

  defp changed_fields_summary([]), do: "Created or removed record"

  defp changed_fields_summary(fields) do
    {shown, rest} = Enum.split(fields, 3)
    label = shown |> Enum.map(&Phoenix.Naming.humanize/1) |> Enum.join(", ")
    if rest == [], do: label, else: label <> " +#{length(rest)} more"
  end

  defp format_time(timestamp), do: ThamaniDawaWeb.TimeFormat.datetime(timestamp)

  def render(assigns) do
    ~H"""
    <Layouts.platform_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/platform/audit"
    >
      <:search>
        <form id="platform-audit-search" phx-change="search" phx-submit="search" onsubmit="return false">
          <.td_search
            name="search"
            value={@filters["search"]}
            placeholder="Search table, organization, or actor"
            shortcut="⌘K"
            phx-debounce="200"
          />
        </form>
      </:search>
      <.td_list_page
        title="Audit activity"
        subtitle="Every audited change across all organizations. Patient-identifying values are not shown."
      >
        <:filters>
          <.td_filter_menu
            id="audit"
            field="table"
            label="Table"
            value={@filters["table"]}
            options={[{"", "Any"} | Enum.map(@tables, &{&1, format_table_name(&1)})]}
          />
          <.td_filter_menu
            id="audit"
            field="user"
            label="Actor"
            value={to_string(@filters["user"])}
            options={[{"", "Any"} | Enum.map(@actors, &{to_string(&1.id), &1.name})]}
          />
          <.td_filter_menu
            id="audit"
            field="action"
            label="Action"
            value={@filters["action"]}
            options={[
              {"", "Any"},
              {"insert", "Created"},
              {"update", "Updated"},
              {"delete", "Deleted"}
            ]}
          />
        </:filters>

      <div class="dashboard-stat-grid">
        <.stat_tile
          id="audit-stat-total"
          icon="hero-clipboard-document-list"
          label="Total changes"
          value={@stats.total}
        />
        <.stat_tile
          id="audit-stat-insert"
          icon="hero-plus-circle"
          label="Created"
          value={@stats.insert}
        />
        <.stat_tile
          id="audit-stat-update"
          icon="hero-pencil-square"
          label="Updated"
          value={@stats.update}
        />
        <.stat_tile id="audit-stat-delete" icon="hero-trash" label="Deleted" value={@stats.delete} />
      </div>

      <.table id="platform-audit-list" rows={@page_info.entries}>
        <:col :let={log} label="Action">
          <div class="flex items-center gap-2">
            <span class={[
              "inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-semibold",
              action_classes(log.action)
            ]}>
              <.icon name={action_icon(log.action)} class="size-3.5" /> {action_label(log.action)}
            </span>
          </div>
          <p class="mt-1 text-xs text-thamani-pewter">{format_time(log.inserted_at)}</p>
        </:col>
        <:col :let={log} label="Table & record">
          <p class="font-medium text-thamani-forest">{format_table_name(log.table_name)}</p>
          <p class="text-xs text-thamani-pewter">Record #{log.record_id}</p>
        </:col>
        <:col :let={log} label="Organization">
          <span class="text-sm">{organization_name(log)}</span>
        </:col>
        <:col :let={log} label="Actor">
          <span class="text-sm">{actor_display(log)}</span>
        </:col>
        <:col :let={log} label="Changes" tablet="hidden">
          <span class="text-xs text-thamani-pewter">{changed_fields_summary(log.changed_fields)}</span>
        </:col>
        <:empty_state>
          <.blank_state icon="hero-clipboard-document-list" title="No audit activity found">
            <%= if @filters["search"] != "" or active_filter_count(@filters) > 0 do %>
              No changes match your current search and filters.
            <% else %>
              No audited activity has been recorded yet.
            <% end %>
          </.blank_state>
        </:empty_state>
      </.table>
      <.pagination page={@page_info} path={pagination_path(@filters)} />
      </.td_list_page>
    </Layouts.platform_shell>
    """
  end
end
