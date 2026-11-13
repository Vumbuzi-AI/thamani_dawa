defmodule ThamaniDawaWeb.DistributorEpcisLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Epcis.Client
  alias ThamaniDawa.Epcis.Outbox
  alias ThamaniDawa.Epcis.OutboxEvent

  def mount(_params, _session, socket) do
    epcis_portal =
      if Scope.admin?(socket.assigns.current_scope), do: :organization, else: :distributor

    epcis_path =
      if epcis_portal == :organization, do: ~p"/org/epcis", else: ~p"/distributor/epcis"

    {:ok,
     socket
     |> assign(:epcis_portal, epcis_portal)
     |> assign(:epcis_path, epcis_path)
     |> assign(:page_title, "PPB reporting")
     |> assign(:inspecting_event, nil)
     |> assign(:selected_status, "all")
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

  def handle_event("inspect_payload", %{"id" => id}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    event = Outbox.get_event!(organization_id, id)
    {:noreply, assign(socket, :inspecting_event, event)}
  end

  def handle_event("close_inspect", _params, socket) do
    {:noreply, assign(socket, :inspecting_event, nil)}
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
           "Event #{short_id(event.event_id)} requeued — it will be resubmitted with the same eventID."
         )}

      _ ->
        {:noreply, put_flash(socket, :error, "Only rejected or dead events can be resubmitted.")}
    end
  end

  defp reload(socket) do
    organization_id = socket.assigns.current_scope.organization_id

    events =
      organization_id
      |> Outbox.list_events(limit: 200)
      |> filter_events(socket.assigns.selected_status)

    socket
    |> assign(:submission_enabled?, Client.enabled?())
    |> assign(:queue_halted?, Outbox.halted?(organization_id))
    |> assign(:status_counts, status_counts(organization_id))
    |> stream(:events, events, reset: true)
  end

  defp status_counts(organization_id) do
    counts = Outbox.count_by_status(organization_id)

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

  defp status_label("accepted"), do: "Accepted"
  defp status_label("warning"), do: "Warning"
  defp status_label("pending"), do: "Pending"
  defp status_label("blocked"), do: "Blocked"
  defp status_label("rejected"), do: "Rejected"
  defp status_label("dead"), do: "Dead"

  defp status_class("accepted"), do: "bg-emerald-50 text-emerald-700 ring-emerald-600/20"
  defp status_class("warning"), do: "bg-amber-100 text-amber-800 ring-amber-600/30"
  defp status_class("pending"), do: "bg-slate-100 text-slate-600 ring-slate-500/20"
  defp status_class("blocked"), do: "bg-amber-100 text-amber-800 ring-amber-600/30"
  defp status_class("rejected"), do: "bg-red-100 text-red-800 ring-red-600/30"
  defp status_class("dead"), do: "bg-red-100 text-red-800 ring-red-600/30"

  defp event_detail(%OutboxEvent{status: "blocked", blocked_reason: reason})
       when is_binary(reason),
       do: reason

  defp event_detail(%OutboxEvent{status: "warning", response: %{"warnings" => warnings}})
       when is_list(warnings),
       do: Enum.join(warnings, " · ")

  defp event_detail(%OutboxEvent{status: status, response: response})
       when status in ["rejected", "dead"] and is_map(response) do
    cond do
      response["error"] -> response["error"]
      response["raw"] -> response["raw"]
      true -> inspect(response)
    end
  end

  defp event_detail(_event), do: nil

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
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@epcis_path}
    >
      {epcis_body(assigns)}
    </Layouts.distributor_shell>
    """
  end

  defp epcis_body(assigns) do
    ~H"""
    <div>
      <.header icon="hero-globe-alt">
        PPB reporting
        <:subtitle>
          Every reportable supply-chain event queued for the PPB National Track &amp; Trace Hub.
        </:subtitle>
        <:actions>
          <.button id="refresh-epcis-events" phx-click="refresh">
            <.icon name="hero-arrow-path" class="size-4" /> Refresh
          </.button>
        </:actions>
      </.header>

      <div
        :if={!@submission_enabled?}
        id="epcis-submission-disabled"
        class="mt-4 flex items-start gap-3 rounded-xl border border-slate-200 bg-white px-4 py-3 text-sm text-thamani-pewter"
      >
        <.icon name="hero-information-circle" class="mt-0.5 size-5 flex-none text-slate-400" />
        <p>
          Hub submission is currently disabled — events are recorded here but not sent.
          Set <code class="font-mono text-xs">PPB_TNT_ENABLED=true</code> with the capture URL and
          API key to go live.
        </p>
      </div>

      <div
        :if={@queue_halted?}
        id="epcis-queue-halted"
        role="alert"
        class="mt-4 flex items-start gap-3 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800"
      >
        <.icon name="hero-exclamation-triangle" class="mt-0.5 size-5 flex-none text-red-500" />
        <p>
          <span class="font-semibold">Reporting is halted.</span> A rejected or dead event is
          blocking this organization's queue — newer events are queued behind it to preserve
          chronological order. Resolve the event below and resubmit it with its original eventID.
        </p>
      </div>

      <div
        id="epcis-status-filters"
        class="mt-4 flex flex-wrap gap-2"
        aria-label="Filter events by status"
      >
        <.status_filter
          status="all"
          label="All"
          count={total_events(@status_counts)}
          selected_status={@selected_status}
          class="bg-white text-thamani-forest"
        />
        <.status_filter
          status="pending"
          label="Pending"
          count={@status_counts["pending"]}
          selected_status={@selected_status}
          class="bg-slate-100 text-slate-600"
        />
        <.status_filter
          status="warning"
          label="Warning"
          count={@status_counts["warning"]}
          selected_status={@selected_status}
          class="bg-amber-100 text-amber-800"
        />
        <.status_filter
          status="blocked"
          label="Blocked"
          count={@status_counts["blocked"]}
          selected_status={@selected_status}
          class="bg-amber-100 text-amber-800"
        />
        <.status_filter
          status="rejected"
          label="Rejected"
          count={@status_counts["rejected"]}
          selected_status={@selected_status}
          class="bg-red-100 text-red-800"
        />
        <.status_filter
          status="dead"
          label="Dead"
          count={@status_counts["dead"]}
          selected_status={@selected_status}
          class="bg-red-100 text-red-800"
        />
        <.status_filter
          status="accepted"
          label="Accepted"
          count={@status_counts["accepted"]}
          selected_status={@selected_status}
          class="bg-emerald-50 text-emerald-700"
        />
      </div>

      <div class="mt-6">
        <.table
          id="epcis-events"
          rows={@streams.events}
          row_id={fn {dom_id, _event} -> dom_id end}
        >
          <:col :let={{_id, event}} label="Event">
            <span class="font-medium capitalize text-thamani-forest">{event.event_type}</span>
            <span class="block font-mono text-xs text-thamani-pewter">
              {Calendar.strftime(event.occurred_at, "%d %b %Y, %H:%M UTC")}
            </span>
          </:col>
          <:col :let={{_id, event}} label="Status">
            <span class={"inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold ring-1 ring-inset #{status_class(event.status)}"}>
              {status_label(event.status)}
            </span>
            <span :if={event.http_status} class="block text-xs text-thamani-pewter">
              HTTP {event.http_status} · attempt {event.attempts}
            </span>
          </:col>
          <:col :let={{_id, event}} label="Detail" mobile="hidden">
            <p
              :if={detail = event_detail(event)}
              class={[
                "max-w-md text-xs leading-5",
                event.status in ["rejected", "dead", "warning", "blocked"] && "font-medium"
              ]}
            >
              {detail}
            </p>
            <p :if={detail == nil} class="text-xs text-thamani-pewter">—</p>
          </:col>
          <:col :let={{_id, event}} label="EventID" tablet="hidden">
            <span class="font-mono text-xs text-thamani-pewter" title={event.event_id}>
              …{short_id(event.event_id)}
            </span>
          </:col>
          <:action :let={{_id, event}}>
            <.button
              id={"inspect-epcis-event-#{event.id}"}
              phx-click="inspect_payload"
              phx-value-id={event.id}
            >
              View payload
            </.button>
            <.button
              :if={event.status in ["rejected", "dead"]}
              id={"resubmit-epcis-event-#{event.id}"}
              variant="primary"
              phx-click="resubmit"
              phx-value-id={event.id}
              data-confirm="Resubmit this event to the PPB Hub with its original eventID?"
            >
              Resubmit
            </.button>
          </:action>
          <:empty_state>
            <.blank_state icon="hero-globe-alt" title="No events yet">
              Receive a delivery or approve a shipment and its EPCIS events will appear here.
            </.blank_state>
          </:empty_state>
        </.table>
      </div>

      <.modal
        :if={@inspecting_event}
        id="epcis-payload-modal"
        show
        on_cancel={JS.push("close_inspect")}
        class="max-w-3xl"
      >
        <h2 id="epcis-payload-modal-title" class="text-lg font-semibold text-thamani-forest">
          {String.capitalize(@inspecting_event.event_type)} event payload
        </h2>
        <p class="mt-1 font-mono text-xs text-thamani-pewter">{@inspecting_event.event_id}</p>
        <pre class="mt-4 max-h-[70vh] overflow-auto rounded-lg bg-slate-900 p-4 text-xs text-slate-100"><code>{Jason.encode!(@inspecting_event.payload, pretty: true)}</code></pre>
        <div :if={@inspecting_event.response} class="mt-4">
          <h3 class="text-sm font-semibold text-thamani-forest">Hub response</h3>
          <pre class="mt-1 max-h-48 overflow-auto rounded-lg bg-slate-900 p-4 text-xs text-slate-100"><code>{Jason.encode!(@inspecting_event.response, pretty: true)}</code></pre>
        </div>
      </.modal>
    </div>
    """
  end

  attr :status, :string, required: true
  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :selected_status, :string, required: true
  attr :class, :string, required: true

  defp status_filter(assigns) do
    ~H"""
    <button
      id={"epcis-filter-#{@status}"}
      type="button"
      phx-click="filter_status"
      phx-value-status={@status}
      aria-pressed={to_string(@selected_status == @status)}
      class={[
        "inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold ring-1 ring-inset transition hover:brightness-95 focus:outline-none focus-visible:ring-2 focus-visible:ring-thamani-forest focus-visible:ring-offset-2",
        @class,
        if(@selected_status == @status, do: "ring-thamani-forest shadow-sm", else: "ring-transparent")
      ]}
    >
      {@count}
      <span class="font-normal opacity-80">{@label}</span>
    </button>
    """
  end
end
