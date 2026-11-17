defmodule ThamaniDawaWeb.PlatformDashboardLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.PlatformMonitoring

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:overview, PlatformMonitoring.overview())
     |> assign(:attention, PlatformMonitoring.organizations_needing_attention())
     |> assign(:activity, PlatformMonitoring.list_recent_activity(5))}
  end

  def render(assigns) do
    ~H"""
    <Layouts.platform_shell flash={@flash} current_scope={@current_scope} current_path="/platform">
      <.header icon="hero-squares-2x2">
        Platform dashboard
        <:subtitle>
          Cross-organization health, recent throughput, and items needing attention.
        </:subtitle>
        <:actions>
          <span class="inline-flex items-center gap-2 rounded-full border border-thamani-stone bg-thamani-canvas px-3 py-2 text-xs font-medium text-thamani-forest">
            <.icon name="hero-shield-check" class="size-4" /> Read-only access
          </span>
        </:actions>
      </.header>

      <div id="platform-overview" class="dashboard-stat-grid">
        <.stat_tile
          id="platform-organizations"
          icon="hero-building-office-2"
          label="Organizations"
          value={@overview.organizations}
          sublabel="Registered on the platform"
        />
        <.stat_tile
          id="platform-active-organizations"
          icon="hero-check-circle"
          label="Active organizations"
          value={@overview.active_organizations}
          sublabel="Currently enabled"
        />
        <.stat_tile
          id="platform-active-users"
          icon="hero-users"
          label="Active users"
          value={@overview.active_users}
          sublabel="Enabled system accounts"
        />
        <.stat_tile
          id="platform-activity"
          icon="hero-clock"
          label="Audited changes"
          value={@overview.activity_last_24h}
          sublabel="Recorded in the last 24 hours"
        />
        <.stat_tile
          id="platform-prescriptions"
          icon="hero-document-text"
          label="Prescriptions"
          value={@overview.prescriptions_last_30d}
          sublabel="Created in the last 30 days"
        />
        <.stat_tile
          id="platform-lab-orders"
          icon="hero-beaker"
          label="Lab orders"
          value={@overview.lab_orders_last_30d}
          sublabel="Created in the last 30 days"
        />
        <.stat_tile
          id="platform-payments"
          icon="hero-banknotes"
          label="Payments"
          value={@overview.payments_last_30d}
          sublabel="Recorded in the last 30 days"
        />
      </div>

      <div
        id="platform-dashboard"
        class="mt-6 grid gap-6 xl:grid-cols-[minmax(0,1.25fr)_minmax(22rem,0.75fr)]"
      >
        <.form_block title="Needs attention">
          <div id="platform-organizations-list" class="divide-y divide-thamani-stone/70">
            <div
              :if={@attention == []}
              id="platform-attention-empty"
              class="py-5 text-sm text-thamani-pewter"
            >
              All active organizations have audited activity in the last seven days.
            </div>
            <div
              :for={summary <- @attention}
              id={"platform-organization-#{summary.organization.id}"}
              class="flex flex-col gap-3 py-4 first:pt-0 last:pb-0 sm:flex-row sm:items-center sm:justify-between"
            >
              <div class="min-w-0">
                <p class="text-sm font-semibold text-thamani-forest">{summary.organization.name}</p>
                <p class="mt-1 text-xs text-thamani-pewter">
                  {Enum.map_join(
                    summary.organization.operating_models || [],
                    " · ",
                    &Phoenix.Naming.humanize/1
                  )}
                </p>
              </div>
              <div class="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-thamani-pewter sm:justify-end">
                <span class="inline-flex items-center gap-1.5"><.icon
                  name="hero-building-office-2"
                  class="size-3.5"
                /> {summary.sites_count} sites</span>
                <span class="inline-flex items-center gap-1.5"><.icon
                  name="hero-users"
                  class="size-3.5"
                /> {summary.users_count} users</span>
                <span>{activity_time(summary.last_activity_at)}</span>
              </div>
            </div>
          </div>
        </.form_block>

        <.form_block title="Recent audited activity">
          <:actions>
            <.link
              navigate={~p"/platform/audit"}
              class="text-xs font-medium text-thamani-forest hover:underline"
            >
              View all activity
            </.link>
          </:actions>
          <ol id="platform-activity-feed" class="divide-y divide-thamani-stone/70">
            <li
              :for={log <- @activity}
              id={"platform-audit-#{log.id}"}
              class="py-4 first:pt-0 last:pb-0"
            >
              <div class="flex items-start gap-3">
                <div class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-lg bg-thamani-stone text-thamani-forest">
                  <.icon name="hero-clock" class="size-4" />
                </div>
                <div class="min-w-0">
                  <p class="truncate text-sm font-semibold text-thamani-forest">
                    {(log.organization && log.organization.name) || "Platform"}
                  </p>
                  <p class="mt-0.5 text-xs text-thamani-pewter">
                    {(log.user && log.user.name) || "System"} · {Phoenix.Naming.humanize(log.action)} {Phoenix.Naming.humanize(
                      log.table_name
                    )}
                  </p>
                  <p class="mt-1 text-xs text-thamani-subtle">{activity_time(log.inserted_at)}</p>
                </div>
              </div>
            </li>
          </ol>
        </.form_block>
      </div>
    </Layouts.platform_shell>
    """
  end

  defp activity_time(nil), do: "No audited activity"
  defp activity_time(timestamp), do: Calendar.strftime(timestamp, "%d %b %Y, %H:%M UTC")
end
