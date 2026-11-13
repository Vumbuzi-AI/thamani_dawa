defmodule ThamaniDawaWeb.PlatformAuditLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.PlatformMonitoring

  def mount(_params, _session, socket) do
    audit_logs = PlatformMonitoring.list_audit_activity(limit: 100)

    {:ok,
     socket
     |> assign(:audit_count, length(audit_logs))
     |> stream(:audit_logs, audit_logs)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.platform_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/platform/audit"
    >
      <.header icon="hero-clipboard-document-list">
        Audit activity
        <:subtitle>
          Latest 100 audited changes across all organizations. Patient-identifying values are not shown.
        </:subtitle>
        <:actions>
          <span class="inline-flex items-center gap-2 rounded-full border border-thamani-stone bg-thamani-canvas px-3 py-2 text-xs font-medium text-thamani-forest">
            <.icon name="hero-shield-check" class="size-4" /> {@audit_count} events
          </span>
        </:actions>
      </.header>

      <.form_block title="Activity timeline">
        <div id="platform-audit-list" phx-update="stream" class="divide-y divide-thamani-stone/70">
          <div
            id="platform-audit-empty"
            class="hidden py-8 text-center text-sm text-thamani-pewter only:block"
          >
            No audited activity yet.
          </div>
          <article
            :for={{id, log} <- @streams.audit_logs}
            id={id}
            class="flex gap-3 py-4 first:pt-0 last:pb-0"
          >
            <div class="mt-0.5 flex size-9 shrink-0 items-center justify-center rounded-lg bg-thamani-stone text-thamani-forest">
              <.icon name="hero-clock" class="size-4" />
            </div>
            <div class="min-w-0 flex-1">
              <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between sm:gap-4">
                <p class="text-sm font-semibold text-thamani-forest">{organization_name(log)}</p>
                <p class="text-xs text-thamani-subtle">{format_time(log.inserted_at)}</p>
              </div>
              <p class="mt-1 text-sm text-slate-700">
                {actor_name(log)}
                <span class="text-thamani-pewter">·</span> {Phoenix.Naming.humanize(log.action)} {Phoenix.Naming.humanize(
                  log.table_name
                )}
              </p>
              <p class="mt-1 text-xs text-thamani-pewter">
                Record #{log.record_id} · {changed_fields(log)}
              </p>
            </div>
          </article>
        </div>
      </.form_block>
    </Layouts.platform_shell>
    """
  end

  defp organization_name(%{organization: %{name: name}}), do: name
  defp organization_name(_log), do: "Platform"

  defp actor_name(%{user: %{name: name}}), do: name
  defp actor_name(_log), do: "System"

  defp changed_fields(%{changed_fields: []}), do: "Created or removed record"
  defp changed_fields(%{changed_fields: fields}), do: "Changed: #{Enum.join(fields, ", ")}"

  defp format_time(timestamp), do: Calendar.strftime(timestamp, "%d %b %Y, %H:%M UTC")
end
