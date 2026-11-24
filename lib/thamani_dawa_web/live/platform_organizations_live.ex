defmodule ThamaniDawaWeb.PlatformOrganizationsLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.PlatformMonitoring

  def mount(_params, _session, socket) do
    summaries = PlatformMonitoring.list_organization_summaries()

    {:ok,
     socket
     |> assign(:search, "")
     |> assign(:summaries, summaries)
     |> assign(:filtered, summaries)
     |> assign(:selected, nil)}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    selected =
      Enum.find(socket.assigns.summaries, fn summary ->
        to_string(summary.organization.id) == id
      end)

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :selected, nil)}
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:filtered, filter_by_search(socket.assigns.summaries, search))}
  end

  defp filter_by_search(summaries, ""), do: summaries

  defp filter_by_search(summaries, search) do
    search = String.downcase(String.trim(search))

    Enum.filter(summaries, fn summary ->
      String.contains?(String.downcase(summary.organization.name), search)
    end)
  end

  defp operating_models(%{operating_models: models}) when is_list(models),
    do: Enum.map_join(models, " · ", &Phoenix.Naming.humanize/1)

  defp operating_models(_organization), do: "—"

  defp status(%{is_active: true}), do: :active
  defp status(%{is_active: false}), do: :inactive

  defp last_activity(nil), do: "No audited activity"
  defp last_activity(timestamp), do: ThamaniDawaWeb.TimeFormat.datetime(timestamp)

  def render(assigns) do
    ~H"""
    <Layouts.platform_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/platform/organizations"
      crumb={if @live_action == :show && @selected, do: @selected.organization.name, else: "Organizations"}
    >
      <.td_list_page
        title="Organizations"
        subtitle="Businesses registered on the platform, with their sites, users, and recent activity."
      >
        <:actions>
          <span class="td-badge">Read-only access</span>
        </:actions>
        <:filters>
          <form phx-change="search" class="flex-1" id="search-form">
            <.search_input name="search" value={@search} placeholder="Search by organization name" />
          </form>
        </:filters>

      <.table
        id="platform-organizations"
        rows={@filtered}
        row_click={fn summary -> JS.navigate(~p"/platform/organizations/#{summary.organization.id}") end}
      >
        <:col :let={summary} label="Organization">{summary.organization.name}</:col>
        <:col :let={summary} label="Activities">
          {operating_models(summary.organization)}
        </:col>
        <:col :let={summary} label="Sites">{summary.sites_count}</:col>
        <:col :let={summary} label="Users">{summary.users_count}</:col>
        <:col :let={summary} label="Last activity">
          {last_activity(summary.last_activity_at)}
        </:col>
        <:col :let={summary} label="Status">
          <.status_badge status={status(summary.organization)} />
        </:col>
        <:empty_state>
          <.blank_state
            icon="hero-building-office-2"
            title={
              if @search != "",
                do: "No organizations match your search",
                else: "No organizations yet"
            }
          >
            {if @search != "",
              do: "Try a different search term.",
              else: "Organizations will appear here once they register on the platform."}
          </.blank_state>
        </:empty_state>
      </.table>
      <div :if={@live_action == :show && @selected} id="platform-organization-detail" class="td-card" style="margin-top:16px;padding:16px">
        <.td_page_header
          title={@selected.organization.name}
          subtitle="Read-only organization record."
        />
        <dl class="td-kv-grid is-pad is-3">
          <div class="td-kv">
            <dt class="td-kv-label">Activities</dt>
            <dd class="td-kv-value">{operating_models(@selected.organization)}</dd>
          </div>
          <div class="td-kv">
            <dt class="td-kv-label">Sites</dt>
            <dd class="td-kv-value">{@selected.sites_count}</dd>
          </div>
          <div class="td-kv">
            <dt class="td-kv-label">Users</dt>
            <dd class="td-kv-value">{@selected.users_count}</dd>
          </div>
          <div class="td-kv">
            <dt class="td-kv-label">Last activity</dt>
            <dd class="td-kv-value">{last_activity(@selected.last_activity_at)}</dd>
          </div>
          <div class="td-kv">
            <dt class="td-kv-label">Status</dt>
            <dd class="td-kv-value"><.status_badge status={status(@selected.organization)} /></dd>
          </div>
        </dl>
      </div>
      <div :if={@live_action == :show && is_nil(@selected)} class="td-empty-state">
        <p class="td-empty-state-title">Organization not found</p>
        <.td_button label="Back to organizations" navigate={~p"/platform/organizations"} />
      </div>
      </.td_list_page>
    </Layouts.platform_shell>
    """
  end
end
