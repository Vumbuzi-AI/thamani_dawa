defmodule ThamaniDawaWeb.ManufacturerEpcisLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Epcis.Client
  alias ThamaniDawa.Epcis.Outbox
  alias ThamaniDawa.Epcis.OutboxEvent
  alias ThamaniDawa.Epcis.SubmissionWorker
  alias ThamaniDawa.Epcis.Urn
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Sites

  def mount(_params, _session, socket) do
    epcis_portal =
      if Scope.admin?(socket.assigns.current_scope), do: :organization, else: :manufacturer

    epcis_path =
      if epcis_portal == :organization, do: ~p"/org/epcis", else: ~p"/manufacturer/epcis"

    {:ok,
     socket
     |> assign(:epcis_portal, epcis_portal)
     |> assign(:epcis_path, epcis_path)
     |> assign(:page_title, "TNT reporting")
     |> assign(:inspecting_event, nil)
     |> assign(:inspection_tab, :request)
     |> assign(:selected_status, "all")
     |> assign(:search_query, "")
     |> stream_configure(:events, dom_id: fn event -> "epcis-events-#{event.id}" end)
     |> reload()}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, reload(socket)}
  end

  def handle_event("filter_status", %{"status" => status}, socket)
      when status in ["all", "pending", "warning", "blocked", "rejected", "dead", "accepted"] do
    {:noreply, socket |> assign(:selected_status, status) |> reload()}
  end

  def handle_event("filter_status", _params, socket), do: {:noreply, socket}

  def handle_event("search", %{"search" => query}, socket) do
    {:noreply, socket |> assign(:search_query, query) |> reload()}
  end

  def handle_event("inspect_payload", %{"id" => id} = params, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    event = Outbox.get_event!(organization_id, id)
    tab = if params["tab"] == "diagnostics", do: :diagnostics, else: :request

    {:noreply, socket |> assign(:inspecting_event, event) |> assign(:inspection_tab, tab)}
  end

  def handle_event("close_inspect", _params, socket) do
    {:noreply, assign(socket, :inspecting_event, nil)}
  end

  def handle_event("select_inspection_tab", %{"tab" => tab}, socket)
      when tab in ["request", "response", "diagnostics"] do
    {:noreply, assign(socket, :inspection_tab, String.to_existing_atom(tab))}
  end

  def handle_event("resubmit", %{"id" => id}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    event = Outbox.get_event!(organization_id, id)

    case Outbox.resubmit(event) do
      %OutboxEvent{status: "pending"} ->
        socket = reload(socket)

        {:noreply,
         put_flash(
           socket,
           :info,
           "Event #{short_id(event.event_id)} requeued. It will be resubmitted with the same eventID."
         )}

      _ ->
        {:noreply,
         put_flash(socket, :error, "Only rejected, dead, or blocked events can be resubmitted.")}
    end
  end

  def handle_event("send_event", %{"id" => id}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    event = Outbox.get_event!(organization_id, id)

    case event.status do
      "pending" ->
        case SubmissionWorker.submit_now(event) do
          {status, _updated} when status in [:accepted, :duplicate] ->
            {:noreply,
             socket
             |> reload()
             |> put_flash(:info, "Event #{short_id(event.event_id)} sent to PPB.")}

          {:rejected, _updated} ->
            {:noreply,
             socket
             |> reload()
             |> put_flash(:error, "PPB rejected event #{short_id(event.event_id)}.")}

          {:retry, _updated} ->
            {:noreply,
             socket
             |> reload()
             |> put_flash(
               :error,
               "Couldn't reach PPB for event #{short_id(event.event_id)} — it will retry automatically."
             )}

          {:blocked, updated} ->
            {:noreply,
             socket
             |> reload()
             |> put_flash(:error, updated.blocked_reason)}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Only pending events can be sent individually.")}
    end
  end

  def handle_event("set_submission_mode", %{"mode" => mode}, socket)
      when mode in ["automatic", "manual"] do
    organization = socket.assigns.organization

    case Organizations.update_epcis_submission_mode(organization, mode) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:organization, updated)
         |> put_flash(
           :info,
           if(mode == "automatic",
             do: "Events will now be sent to PPB automatically as they're queued.",
             else: "Events will now wait here until you send them manually."
           )
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't update the submission mode.")}
    end
  end

  def handle_event("send_now", _params, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    pending = socket.assigns.status_counts["pending"]

    if pending > 0 do
      SubmissionWorker.enqueue_now(organization_id)

      {:noreply,
       socket
       |> reload()
       |> put_flash(
         :info,
         "Sending #{pending} pending event#{if pending == 1, do: "", else: "s"} to PPB now."
       )}
    else
      {:noreply, put_flash(socket, :error, "There are no pending events to send.")}
    end
  end

  defp key_last4(organization, "distributor"), do: organization.epcis_distributor_api_key_last4
  defp key_last4(organization, "facility"), do: organization.epcis_facility_api_key_last4
  defp key_last4(organization, "manufacturer"), do: organization.epcis_manufacturer_api_key_last4

  defp tnt_keys_missing?(organization) do
    organization
    |> relevant_tiers()
    |> Enum.any?(&(key_last4(organization, &1) in [nil, ""]))
  end

  defp api_keys_path(%{assigns: %{epcis_portal: :organization}}), do: ~p"/org/api-keys"
  defp api_keys_path(_socket), do: ~p"/manufacturer/api-keys"

  defp reload(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    organization = Organizations.get_organization!(organization_id)

    events =
      organization_id
      |> Outbox.list_events(limit: 200, tier: "manufacturer")
      |> filter_events(socket.assigns.selected_status)
      |> filter_by_search(socket.assigns.search_query)

    socket
    |> assign(:organization, organization)
    |> assign(:tnt_keys_missing?, tnt_keys_missing?(organization))
    |> assign(:api_keys_path, api_keys_path(socket))
    |> assign(:submission_enabled?, Client.enabled?())
    |> assign(:queue_halted?, Outbox.halted?(organization_id))
    |> assign(:status_counts, status_counts(organization_id))
    |> assign(:site_names, site_names_by_gln(organization_id))
    |> stream(:events, events, reset: true)
  end

  defp site_names_by_gln(organization_id) do
    organization_id
    |> Sites.list_sites()
    |> Map.new(&{&1.gln, &1.name})
  end

  defp filter_by_search(events, query) when is_binary(query) do
    query = query |> String.trim() |> String.downcase()

    if query == "" do
      events
    else
      Enum.filter(events, fn event ->
        String.contains?(String.downcase(event.event_type), query) or
          String.contains?(String.downcase(event.event_id), query) or
          String.contains?(String.downcase(short_id(event.event_id)), query)
      end)
    end
  end

  defp event_site_name(%OutboxEvent{payload: %{"bizLocation" => %{"id" => urn}}}, site_names) do
    case Urn.gln_from_sgln(urn) do
      {:ok, gln} -> Map.get(site_names, gln)
      :error -> nil
    end
  end

  defp event_site_name(_event, _site_names), do: nil

  defp status_counts(organization_id) do
    counts = Outbox.count_by_status(organization_id, tier: "manufacturer")

    Map.merge(
      %{
        "pending" => 0,
        "blocked" => 0,
        "accepted" => 0,
        "warning" => 0,
        "rejected" => 0,
        "dead" => 0
      },
      counts
    )
  end

  defp filter_events(events, "all"), do: events
  defp filter_events(events, status), do: Enum.filter(events, &(&1.status == status))

  defp total_events(counts), do: counts |> Map.values() |> Enum.sum()

  defp selected_filter_label("all"), do: "All events"
  defp selected_filter_label("accepted"), do: "Accepted"
  defp selected_filter_label("warning"), do: "Warning"
  defp selected_filter_label("pending"), do: "Pending"
  defp selected_filter_label("blocked"), do: "Blocked"
  defp selected_filter_label("rejected"), do: "Rejected"
  defp selected_filter_label("dead"), do: "Dead"
  defp selected_filter_label(status), do: String.capitalize(status)

  defp status_label("accepted"), do: "Accepted"
  defp status_label("warning"), do: "Warning"
  defp status_label("pending"), do: "Pending"
  defp status_label("blocked"), do: "Blocked"
  defp status_label("rejected"), do: "Rejected"
  defp status_label("dead"), do: "Dead"
  defp status_label(status), do: String.capitalize(status)

  defp status_class("accepted"), do: "bg-td-accent-tint text-thamani-forest"
  defp status_class("warning"), do: "bg-amber-900 text-amber-50"
  defp status_class("pending"), do: "bg-thamani-stone text-thamani-forest"
  defp status_class("blocked"), do: "bg-amber-900 text-amber-50"
  defp status_class("rejected"), do: "bg-thamani-error text-td-on-danger"
  defp status_class("dead"), do: "bg-thamani-error text-td-on-danger"
  defp status_class(_status), do: "bg-thamani-stone text-thamani-forest"

  defp event_detail(%OutboxEvent{status: "blocked", blocked_reason: reason})
       when is_binary(reason),
       do: reason

  defp event_detail(%OutboxEvent{status: "warning", response: %{"warnings" => warnings}})
       when is_list(warnings),
       do: warnings |> Enum.map(&warning_message/1) |> Enum.join(" · ")

  defp event_detail(%OutboxEvent{status: status, response: response})
       when status in ["rejected", "dead"] and is_map(response) do
    cond do
      response["error"] -> response["error"]
      response["raw"] -> response["raw"]
      true -> inspect(response)
    end
  end

  defp event_detail(_event), do: nil

  defp warning_message(%{"message" => message}) when is_binary(message), do: message
  defp warning_message(message) when is_binary(message), do: message
  defp warning_message(warning), do: inspect(warning)

  defp short_id(event_id), do: String.slice(event_id, -8, 8)

  def render(%{epcis_portal: :organization} = assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path={@epcis_path}>
      {epcis_body(assigns)}
    </Layouts.org_shell>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@epcis_path}
    >
      {epcis_body(assigns)}
    </Layouts.manufacturer_shell>
    """
  end

  defp epcis_body(assigns) do
    ~H"""
    <div class="space-y-5">
      <.td_page_header
        title="TNT reporting"
        subtitle="Report supply-chain events to the PPB National Track & Trace Hub."
      />

      <div
        :if={!@submission_enabled?}
        id="epcis-submission-disabled"
        class="flex items-start gap-3 rounded-2xl border border-thamani-frosted bg-td-surface px-4 py-3 text-sm text-thamani-pewter"
      >
        <.icon name="hero-information-circle" class="mt-0.5 size-5 flex-none text-thamani-pewter" />
        <p>
          <span class="font-semibold text-thamani-forest">PPB submission is not active yet.</span>
          Events are safely recorded here, but will not be sent until your system administrator
          enables the Hub connection.
        </p>
      </div>

      <div
        :if={@queue_halted?}
        id="epcis-queue-halted"
        role="alert"
        class="flex items-start gap-3 rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800"
      >
        <.icon name="hero-exclamation-triangle" class="mt-0.5 size-5 flex-none text-red-600" />
        <p>
          <span class="font-semibold">Reporting is halted.</span> A rejected or dead event is
          blocking this organization's queue — newer events are queued behind it to preserve
          chronological order. Resolve the event below and resubmit it with its original eventID.
        </p>
      </div>

      <p :if={@tnt_keys_missing?} id="epcis-api-keys-link" class="text-sm text-thamani-pewter">
        Add your TNT API key on
        <.link
          navigate={@api_keys_path}
          class="font-semibold text-thamani-forest underline-offset-2 hover:underline"
        >
          API keys
        </.link>
        before you send events.
      </p>

      {epcis_settings(assigns)}

      <section class="overflow-hidden rounded-2xl border border-thamani-frosted bg-td-surface">
        <div class="flex flex-col gap-4 border-b border-thamani-frosted px-4 py-4 sm:px-5 lg:flex-row lg:items-center lg:justify-between">
          <div>
            <h2 class="text-base font-semibold text-thamani-forest">Events</h2>
            <p class="mt-0.5 text-sm text-thamani-pewter">
              What has been queued or sent for this organization.
            </p>
          </div>
          <.td_button id="refresh-epcis-events" variant="secondary" label="Refresh" phx-click="refresh" />
        </div>

        <div class="flex flex-col gap-3 border-b border-thamani-frosted px-4 py-3 sm:flex-row sm:items-center sm:px-5">
          <div id="epcis-status-filters" class="relative">
            <button
              id="status-filter-dropdown-button"
              type="button"
              phx-click={
                JS.toggle(to: "#status-filter-dropdown-menu")
                |> JS.toggle_class("rotate-180", to: "#status-dropdown-chevron")
              }
              class="inline-flex w-full items-center justify-between gap-2 rounded-full border border-thamani-frosted bg-td-surface px-4 py-2 text-sm font-medium text-thamani-forest transition hover:border-thamani-forest focus:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent sm:w-auto"
              aria-haspopup="true"
              aria-expanded="false"
            >
              <span>{selected_filter_label(@selected_status)}</span>
              <span id="status-dropdown-chevron" class="inline-flex transition-transform">
                <.icon name="hero-chevron-down" class="size-4 text-thamani-pewter" />
              </span>
            </button>

            <div
              id="status-filter-dropdown-menu"
              class="absolute left-0 z-10 mt-2 hidden w-64 rounded-xl border border-thamani-frosted bg-td-surface py-1"
              role="menu"
              aria-labelledby="status-filter-dropdown-button"
            >
              <.status_filter_option
                status="all"
                label="All events"
                count={total_events(@status_counts)}
                selected_status={@selected_status}
                icon="hero-queue-list"
              />
              <.status_filter_option
                status="pending"
                label="Pending"
                count={@status_counts["pending"]}
                selected_status={@selected_status}
                icon="hero-clock"
              />
              <.status_filter_option
                status="warning"
                label="Warning"
                count={@status_counts["warning"]}
                selected_status={@selected_status}
                icon="hero-exclamation-triangle"
              />
              <.status_filter_option
                status="blocked"
                label="Blocked"
                count={@status_counts["blocked"]}
                selected_status={@selected_status}
                icon="hero-hand-raised"
              />
              <.status_filter_option
                status="rejected"
                label="Rejected"
                count={@status_counts["rejected"]}
                selected_status={@selected_status}
                icon="hero-x-circle"
              />
              <.status_filter_option
                status="dead"
                label="Dead"
                count={@status_counts["dead"]}
                selected_status={@selected_status}
                icon="hero-no-symbol"
              />
              <.status_filter_option
                status="accepted"
                label="Accepted"
                count={@status_counts["accepted"]}
                selected_status={@selected_status}
                icon="hero-check-circle"
              />
            </div>
          </div>

          <form phx-change="search" id="epcis-event-search-form" class="min-w-0 flex-1">
            <.search_input
              name="search"
              value={@search_query}
              placeholder="Search by action or event ID"
            />
          </form>
        </div>

        <div id="epcis-events" phx-update="stream" class="divide-y divide-thamani-frosted">
          <div id="epcis-events-empty" class="hidden px-4 py-6 only:block">
            <.blank_state icon="hero-globe-alt" title="No events yet">
              Generate serials or create an SSCC and its EPCIS events will appear here.
            </.blank_state>
          </div>
          <.event_row
            :for={{id, event} <- @streams.events}
            id={id}
            event={event}
            site_names={@site_names}
          />
        </div>
      </section>

      <.modal
        :if={@inspecting_event}
        id="epcis-payload-modal"
        show
        on_cancel={JS.push("close_inspect")}
        class="max-w-3xl"
      >
        <h2 id="epcis-payload-modal-title" class="text-lg font-semibold text-thamani-forest">
          {String.capitalize(@inspecting_event.event_type)} event details
        </h2>
        <p class="mt-1 text-xs tabular-nums tracking-tight text-thamani-pewter">
          {@inspecting_event.event_id}
        </p>
        <div class="mt-5 flex gap-1 border-b border-thamani-stone">
          <button
            :for={
              {tab, label} <- [
                request: "Request",
                response: "Response",
                diagnostics: "Warnings & errors"
              ]
            }
            type="button"
            phx-click="select_inspection_tab"
            phx-value-tab={tab}
            class={[
              "border-b-2 px-3 py-2 text-sm font-medium",
              if(@inspection_tab == tab,
                do: "border-thamani-forest text-thamani-forest",
                else: "border-transparent text-thamani-pewter hover:text-thamani-forest"
              )
            ]}
          >{label}</button>
        </div>
        <pre
          :if={@inspection_tab == :request}
          class="mt-4 max-h-[55vh] overflow-auto rounded-lg bg-td-ink p-4 text-xs text-td-wash"
        ><code>{Jason.encode!(@inspecting_event.payload, pretty: true)}</code></pre>
        <pre
          :if={@inspection_tab == :response and @inspecting_event.response}
          class="mt-4 max-h-[55vh] overflow-auto rounded-lg bg-td-ink p-4 text-xs text-td-wash"
        ><code>{Jason.encode!(@inspecting_event.response, pretty: true)}</code></pre>
        <p
          :if={@inspection_tab == :response and is_nil(@inspecting_event.response)}
          class="mt-4 text-sm text-thamani-pewter"
        >
          No response has been received yet.
        </p>
        <p
          :if={@inspection_tab == :diagnostics and is_nil(event_detail(@inspecting_event))}
          class="mt-4 text-sm text-thamani-pewter"
        >
          No warnings or errors were recorded for this event.
        </p>
        <p
          :if={@inspection_tab == :diagnostics and event_detail(@inspecting_event)}
          class="mt-4 rounded-lg bg-amber-50 p-4 text-sm leading-6 text-amber-900"
        >
          {event_detail(@inspecting_event)}
        </p>
      </.modal>
    </div>
    """
  end

  defp epcis_settings(assigns) do
    assigns = assign(assigns, :pending_count, assigns.status_counts["pending"])

    ~H"""
    <section
      id="epcis-reporting-controls"
      class="rounded-2xl border border-thamani-frosted bg-td-surface p-5 sm:p-6"
    >
      <div class="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <h2 class="text-base font-semibold text-thamani-forest">How events are sent</h2>
          <p class="mt-1 text-sm text-thamani-pewter">
            {if @organization.epcis_submission_mode == :automatic,
              do: "Events go to PPB as soon as they are queued.",
              else: "Events wait here until you send them."}
          </p>
          <div
            aria-label="Reporting mode"
            class="mt-3 inline-flex items-center gap-1 rounded-full bg-thamani-stone p-1"
          >
            <button
              type="button"
              id="epcis-mode-automatic"
              phx-click="set_submission_mode"
              phx-value-mode="automatic"
              aria-pressed={to_string(@organization.epcis_submission_mode == :automatic)}
              class={[
                "inline-flex items-center gap-1.5 rounded-full px-4 py-2 text-sm font-medium transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent",
                if(@organization.epcis_submission_mode == :automatic,
                  do: "bg-td-surface text-thamani-forest",
                  else: "text-thamani-pewter hover:text-thamani-forest"
                )
              ]}
            >
              <.icon name="hero-bolt" class="size-4" /> Automatic
            </button>
            <button
              type="button"
              id="epcis-mode-manual"
              phx-click="set_submission_mode"
              phx-value-mode="manual"
              aria-pressed={to_string(@organization.epcis_submission_mode == :manual)}
              class={[
                "inline-flex items-center gap-1.5 rounded-full px-4 py-2 text-sm font-medium transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent",
                if(@organization.epcis_submission_mode == :manual,
                  do: "bg-thamani-forest text-td-on-accent",
                  else: "text-thamani-pewter hover:text-thamani-forest"
                )
              ]}
            >
              <.icon name="hero-hand-raised" class="size-4" /> Manual
            </button>
          </div>
        </div>

        <div class="flex flex-col gap-3 sm:flex-row sm:items-center">
          <p class="text-sm text-thamani-pewter">
            <span class="font-semibold tabular-nums text-thamani-forest">{@pending_count}</span>
            {if @pending_count == 1, do: "event waiting", else: "events waiting"}
          </p>
          <.button
            id="epcis-send-now"
            variant="primary"
            phx-click="send_now"
            disabled={@organization.epcis_submission_mode != :manual or @pending_count == 0}
            data-confirm={"Send #{@pending_count} pending event(s) to the PPB Hub now?"}
            class="w-full sm:w-auto"
          >
            <.icon name="hero-paper-airplane" class="size-4" /> Send pending now
          </.button>
        </div>
      </div>
    </section>
    """
  end

  defp relevant_tiers(organization) do
    models = organization.operating_models || []

    [
      :distributor in models && "distributor",
      :manufacturer in models && "manufacturer",
      Enum.any?(models, &(&1 in [:pharmacy, :laboratory])) && "facility"
    ]
    |> Enum.filter(& &1)
  end

  attr :id, :string, required: true
  attr :event, :map, required: true
  attr :site_names, :map, required: true

  defp event_row(assigns) do
    ~H"""
    <article id={@id} class="px-4 py-3.5 sm:px-5">
      <div class="flex flex-col gap-3 lg:flex-row lg:items-center lg:gap-6">
        <div class="min-w-0 lg:w-64 lg:shrink-0">
          <p class="truncate text-sm font-semibold capitalize text-thamani-forest">
            {@event.event_type}
          </p>
          <p class="mt-0.5 text-xs text-thamani-pewter">
            <span class="tabular-nums">
              {Calendar.strftime(@event.occurred_at, "%d %b %Y, %H:%M UTC")}
            </span>
            <span class="mx-1.5 text-thamani-subtle" aria-hidden="true">·</span>
            <span class="tabular-nums tracking-tight" title={@event.event_id}>
              {short_id(@event.event_id)}
            </span>
          </p>
        </div>

        <div class="flex items-center gap-3 lg:w-36 lg:shrink-0">
          <span class={[
            "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-medium",
            status_class(@event.status)
          ]}>
            {status_label(@event.status)}
          </span>
          <span :if={@event.http_status} class="text-xs tabular-nums text-thamani-pewter">
            HTTP {@event.http_status}
          </span>
        </div>

        <p class="min-w-0 flex-1 text-sm text-thamani-forest [overflow-wrap:anywhere]">
          {event_site_name(@event, @site_names) || "—"}
        </p>

        <div class="flex flex-wrap items-center justify-end gap-2">
          <.button
            id={"inspect-epcis-event-#{@event.id}"}
            phx-click="inspect_payload"
            phx-value-id={@event.id}
          >
            View details
          </.button>
          <.button
            :if={event_detail(@event)}
            id={"review-diagnostics-epcis-event-#{@event.id}"}
            phx-click="inspect_payload"
            phx-value-id={@event.id}
            phx-value-tab="diagnostics"
          >
            Review diagnostics
          </.button>
          <.button
            :if={@event.status in ["rejected", "dead", "blocked"]}
            id={"resubmit-epcis-event-#{@event.id}"}
            variant="primary"
            phx-click="resubmit"
            phx-value-id={@event.id}
            data-confirm="Resubmit this event to the PPB Hub with its original eventID?"
          >
            Resubmit
          </.button>
          <.button
            :if={@event.status == "pending"}
            id={"send-epcis-event-#{@event.id}"}
            variant="primary"
            phx-click="send_event"
            phx-value-id={@event.id}
            data-confirm="Send this event to the PPB Hub now, ahead of its place in the queue?"
          >
            Send
          </.button>
        </div>
      </div>
    </article>
    """
  end

  attr :status, :string, required: true
  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :selected_status, :string, required: true
  attr :icon, :string, required: true

  defp status_filter_option(assigns) do
    ~H"""
    <button
      id={"epcis-filter-#{@status}"}
      type="button"
      phx-click={
        JS.push("filter_status", value: %{status: @status})
        |> JS.hide(to: "#status-filter-dropdown-menu")
        |> JS.remove_class("rotate-180", to: "#status-dropdown-chevron")
      }
      role="menuitem"
      aria-pressed={to_string(@selected_status == @status)}
      class={[
        "flex w-full items-center gap-3 px-4 py-2 text-sm transition hover:bg-td-wash",
        if(@selected_status == @status,
          do: "bg-thamani-forest/5 text-thamani-forest",
          else: "text-thamani-pewter"
        )
      ]}
    >
      <.icon name={@icon} class="size-4 flex-none" />
      <span class="flex-1 text-left">{@label}</span>
      <span class={[
        "flex-none rounded-full px-2 py-0.5 text-xs font-semibold",
        if(@selected_status == @status,
          do: "bg-thamani-forest text-td-on-accent",
          else: "bg-td-wash text-td-ink-2"
        )
      ]}>
        {@count}
      </span>
    </button>
    """
  end
end
