defmodule ThamaniDawaWeb.PlatformOrganizationsLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.PlatformMonitoring

  def mount(_params, _session, socket) do
    summaries = PlatformMonitoring.list_organization_summaries()

    {:ok,
     socket
     |> assign(:search, "")
     |> assign(:summaries, summaries)
     |> assign(:filtered, summaries)}
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
  defp last_activity(timestamp), do: Calendar.strftime(timestamp, "%d %b %Y, %H:%M UTC")

  def render(assigns) do
    ~H"""
    <Layouts.platform_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/platform/organizations"
    >
      <.header icon="hero-building-office-2">
        Organizations
        <:subtitle>
          Businesses registered on the platform, with their sites, users, and recent activity.
        </:subtitle>
        <:actions>
          <span class="inline-flex items-center gap-2 rounded-full border border-thamani-stone bg-thamani-canvas px-3 py-2 text-xs font-medium text-thamani-forest">
            <.icon name="hero-shield-check" class="size-4" /> Read-only access
          </span>
        </:actions>
        <:toolbar>
          <form phx-change="search" class="flex-1" id="search-form">
            <.search_input name="search" value={@search} placeholder="Search by organization name" />
          </form>
        </:toolbar>
      </.header>

      <.table id="platform-organizations" rows={@filtered}>
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
    </Layouts.platform_shell>
    """
  end
end
