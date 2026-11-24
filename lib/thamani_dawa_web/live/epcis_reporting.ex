defmodule ThamaniDawaWeb.EpcisReporting do
  @moduledoc false
  use ThamaniDawaWeb, :html

  alias ThamaniDawa.Epcis.OutboxEvent
  alias ThamaniDawa.Epcis.Urn

  attr :empty_copy, :string, required: true
  attr :organization, :map, required: true
  attr :status_counts, :map, required: true
  attr :selected_status, :string, required: true
  attr :search_query, :string, required: true
  attr :submission_enabled?, :boolean, required: true
  attr :queue_halted?, :boolean, required: true
  attr :tnt_keys_missing?, :boolean, required: true
  attr :api_keys_path, :string, required: true
  attr :streams, :map, required: true
  attr :site_names, :map, required: true
  attr :inspecting_event, :any, default: nil
  attr :inspection_tab, :atom, default: :request
  attr :confirm_action, :any, default: nil

  def epcis_body(assigns) do
    assigns = assign(assigns, :pending_count, assigns.status_counts["pending"] || 0)

    ~H"""
    <div class="td-stack">
      <.td_page_header
        title="TNT reporting"
        subtitle="Report supply-chain events to the PPB National Track and Trace Hub."
      />

      <div
        :if={!@submission_enabled?}
        id="epcis-submission-disabled"
        class="td-notice"
      >
        <.td_icon name="info" />
        <p>
          PPB submission is not active yet. Events are safely recorded here, but will not be sent until your system administrator enables the Hub connection.
        </p>
      </div>

      <div
        :if={@queue_halted?}
        id="epcis-queue-halted"
        role="alert"
        class="td-notice is-danger"
      >
        <.td_icon name="warning" />
        <p>
          <b>Reporting is halted.</b>
          A failed event is blocking this organization's queue. Resolve it below and resubmit it with its original event ID.
        </p>
      </div>

      <p :if={@tnt_keys_missing?} id="epcis-api-keys-link" class="td-hint">
        <.td_icon name="key" />
        Add your TNT API key on
        <.link navigate={@api_keys_path} class="td-hint-link">API keys</.link>
        before you send events.
      </p>

      <section id="epcis-reporting-controls" class="td-card">
        <.td_card_header
          title="How events are sent"
          subtitle={
            if @organization.epcis_submission_mode == :automatic,
              do: "Events go to PPB as soon as they are queued.",
              else: "Events wait here until you send them."
          }
        />
        <div class="td-tnt-controls">
          <.td_segmented>
            <.td_segment
              id="epcis-mode-automatic"
              label="Automatic"
              active={@organization.epcis_submission_mode == :automatic}
              aria-pressed={to_string(@organization.epcis_submission_mode == :automatic)}
              phx-click="set_submission_mode"
              phx-value-mode="automatic"
            />
            <.td_segment
              id="epcis-mode-manual"
              label="Manual"
              active={@organization.epcis_submission_mode == :manual}
              aria-pressed={to_string(@organization.epcis_submission_mode == :manual)}
              phx-click="set_submission_mode"
              phx-value-mode="manual"
            />
          </.td_segmented>
          <p class="td-tnt-waiting">
            <b>{@pending_count}</b>
            {if @pending_count == 1, do: "event waiting", else: "events waiting"}
          </p>
          <.td_button
            id="epcis-send-now"
            variant="primary"
            label="Send pending now"
            glyph="paper-plane-tilt"
            phx-click="prompt_send_now"
            disabled={
              @organization.epcis_submission_mode != :manual or @pending_count == 0 or
                @tnt_keys_missing?
            }
          />
        </div>
      </section>

      <section class="td-card">
        <.td_card_header title="Events" subtitle="What has been queued or sent for this organization.">
          <:actions>
            <.td_button
              id="refresh-epcis-events"
              variant="secondary"
              label="Refresh"
              glyph="arrows-clockwise"
              phx-click="refresh"
            />
          </:actions>
        </.td_card_header>

        <div class="td-tnt-toolbar">
          <div id="epcis-status-filters" class="relative">
            <button
              id="status-filter-dropdown-button"
              type="button"
              phx-click={
                JS.toggle(to: "#status-filter-dropdown-menu")
                |> JS.toggle_class("rotate-180", to: "#status-dropdown-chevron")
              }
              class="td-filter-btn"
              aria-haspopup="true"
              aria-expanded="false"
            >
              <.td_icon name="funnel" />
              <span>{selected_filter_label(@selected_status)}</span>
              <span id="status-dropdown-chevron" class="inline-flex transition-transform">
                <.td_icon name="caret-down" />
              </span>
            </button>
            <div
              id="status-filter-dropdown-menu"
              class="td-row-menu-list hidden"
              role="menu"
              aria-labelledby="status-filter-dropdown-button"
            >
              <.status_filter_option
                status="all"
                label="All events"
                count={total_events(@status_counts)}
                selected_status={@selected_status}
                icon="list"
              />
              <.status_filter_option
                status="pending"
                label="Pending"
                count={@status_counts["pending"]}
                selected_status={@selected_status}
                icon="clock"
              />
              <.status_filter_option
                status="warning"
                label="Warning"
                count={@status_counts["warning"]}
                selected_status={@selected_status}
                icon="warning"
              />
              <.status_filter_option
                status="blocked"
                label="Blocked"
                count={@status_counts["blocked"]}
                selected_status={@selected_status}
                icon="hand"
              />
              <.status_filter_option
                status="rejected"
                label="Rejected"
                count={@status_counts["rejected"]}
                selected_status={@selected_status}
                icon="x-circle"
              />
              <.status_filter_option
                status="dead"
                label="Dead"
                count={@status_counts["dead"]}
                selected_status={@selected_status}
                icon="minus-circle"
              />
              <.status_filter_option
                status="accepted"
                label="Accepted"
                count={@status_counts["accepted"]}
                selected_status={@selected_status}
                icon="check-circle"
              />
            </div>
          </div>
          <form phx-change="search" id="epcis-event-search-form" class="min-w-0 flex-1">
            <.td_search name="search" value={@search_query} placeholder="Search by action or event ID" />
          </form>
        </div>

        <div class="td-table-wrap">
          <table class="td-table">
            <thead>
              <tr>
                <th>Event</th>
                <th>Time (EAT)</th>
                <th>Event ID</th>
                <th>Status</th>
                <th>Location</th>
                <th></th>
              </tr>
            </thead>
            <tbody id="epcis-events" phx-update="stream">
              <tr id="epcis-events-empty" class="hidden only:table-row">
                <td colspan="6">
                  <div class="td-empty">
                    <p class="td-empty-title">No events yet</p>
                    <p class="td-note">{@empty_copy}</p>
                  </div>
                </td>
              </tr>
              <.event_row
                :for={{id, event} <- @streams.events}
                id={id}
                event={event}
                site_names={@site_names}
              />
            </tbody>
          </table>
        </div>
      </section>

      <.details_modal
        :if={@inspecting_event}
        event={@inspecting_event}
        tab={@inspection_tab}
        site_names={@site_names}
      />

      <.confirm_modal :if={@confirm_action} action={@confirm_action} pending_count={@pending_count} />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :event, :map, required: true
  attr :site_names, :map, required: true

  defp event_row(assigns) do
    {label, tone} = display_status(assigns.event.status)
    assigns = assign(assigns, display_label: label, display_tone: tone)

    ~H"""
    <tr id={@id}>
      <td>
        <b>{business_step_label(@event)}</b>
        <span class="td-sub">{event_type_label(@event)}</span>
      </td>
      <td>{format_eat(@event.occurred_at)}</td>
      <td><span class="td-mono">{short_id(@event.event_id)}</span></td>
      <td>
        <span class={["td-badge", "is-#{@display_tone}"]}>{@display_label}</span>
      </td>
      <td>{event_site_name(@event, @site_names) || "—"}</td>
      <td>
        <div class="td-tnt-actions">
          <.td_button
            id={"inspect-epcis-event-#{@event.id}"}
            variant="secondary"
            label="View details"
            phx-click="inspect_payload"
            phx-value-id={@event.id}
          />
          <.td_button
            :if={@event.status == "pending"}
            id={"send-epcis-event-#{@event.id}"}
            variant="primary"
            label="Send"
            phx-click="prompt_send_event"
            phx-value-id={@event.id}
          />
          <.td_button
            :if={@event.status in ["rejected", "dead", "blocked"]}
            id={"resubmit-epcis-event-#{@event.id}"}
            variant="primary"
            label="Resubmit"
            phx-click="prompt_resubmit"
            phx-value-id={@event.id}
          />
        </div>
      </td>
    </tr>
    """
  end

  attr :event, :map, required: true
  attr :tab, :atom, required: true
  attr :site_names, :map, required: true

  defp details_modal(assigns) do
    event = assigns.event
    {label, _tone} = display_status(event.status)
    gln = event_gln(event)

    assigns =
      assigns
      |> assign(:display_label, label)
      |> assign(:biz, business_step_label(event))
      |> assign(:type_label, event_type_label(event))
      |> assign(:site, event_site_name(event, assigns.site_names))
      |> assign(:gln, gln)
      |> assign(:identifiers, identifiers(event))
      |> assign(:batch, batch_of(event))
      |> assign(:disposition, disposition_of(event))
      |> assign(:detail, event_detail(event))
      |> assign(:show_json?, assigns.tab in [:request, :response, :diagnostics])

    ~H"""
    <.td_modal
      id="epcis-payload-modal"
      show
      title={"#{@biz} event"}
      subtitle={"#{@type_label} · #{short_id(@event.event_id)}"}
      on_cancel={JS.push("close_inspect")}
    >
      <:body>
        <div class="td-stack">
          <section :if={@identifiers != [] or @batch}>
            <h3 class="td-k">What</h3>
            <p :for={id <- @identifiers} class="td-mono">{id}</p>
            <p :if={@batch}><span class="td-k">Batch</span> <span class="td-mono">{@batch}</span></p>
          </section>
          <section>
            <h3 class="td-k">Where</h3>
            <p :if={@site}>{@site}</p>
            <p :if={@gln} class="td-mono">{@gln}</p>
            <p :if={!@site and !@gln} class="td-note">No location recorded.</p>
          </section>
          <section>
            <h3 class="td-k">When</h3>
            <p>Event time {format_eat(@event.occurred_at)} EAT</p>
            <p :if={@event.inserted_at}>Recorded {format_eat(@event.inserted_at)} EAT</p>
          </section>
          <section>
            <h3 class="td-k">Why</h3>
            <p>{@biz}</p>
            <p :if={@disposition}>{Phoenix.Naming.humanize(@disposition)}</p>
          </section>
          <section>
            <h3 class="td-k">Payload</h3>
            <p>Status {@display_label}</p>
            <p :if={@event.http_status}>Hub response HTTP {@event.http_status}</p>
            <p :if={@detail}>{@detail}</p>
            <div class="td-tnt-json-tabs">
              <button type="button" phx-click="select_inspection_tab" phx-value-tab="request">
                Request
              </button>
              <button type="button" phx-click="select_inspection_tab" phx-value-tab="response">
                Response
              </button>
            </div>
            <pre
              :if={@tab == :request}
              class="td-json"
            ><code>{Jason.encode!(@event.payload, pretty: true)}</code></pre>
            <pre
              :if={@tab == :response and @event.response}
              class="td-json"
            ><code>{Jason.encode!(@event.response, pretty: true)}</code></pre>
            <p :if={@tab == :response and is_nil(@event.response)} class="td-note">
              No response has been received yet.
            </p>
          </section>
        </div>
      </:body>
      <:footer>
        <.td_button type="button" variant="secondary" label="Close" phx-click="close_inspect" />
        <.td_button
          :if={@event.status == "pending"}
          id={"details-send-epcis-event-#{@event.id}"}
          variant="primary"
          label="Send"
          phx-click="prompt_send_event"
          phx-value-id={@event.id}
        />
      </:footer>
    </.td_modal>
    """
  end

  attr :action, :any, required: true
  attr :pending_count, :integer, required: true

  defp confirm_modal(%{action: :send_now} = assigns) do
    n = assigns.pending_count

    assigns =
      assign(assigns,
        title: "Send #{n} pending event#{if n == 1, do: "", else: "s"} now?",
        body: "They go to the PPB Hub in the order they were recorded.",
        confirm_id: "epcis-send-now-confirm",
        confirm_label: "Send #{n} event#{if n == 1, do: "", else: "s"}",
        confirm_event: "send_now",
        confirm_id_value: nil
      )

    confirm_markup(assigns)
  end

  defp confirm_modal(%{action: {:send_event, id}} = assigns) do
    assigns =
      assign(assigns,
        title: "Send this event now?",
        body: "It goes to the PPB Hub ahead of its place in the queue, with its original event ID.",
        confirm_id: "send-epcis-event-#{id}-confirm",
        confirm_label: "Send",
        confirm_event: "send_event",
        confirm_id_value: id
      )

    confirm_markup(assigns)
  end

  defp confirm_modal(%{action: {:resubmit, id}} = assigns) do
    assigns =
      assign(assigns,
        title: "Resubmit this event?",
        body: "It is sent to the PPB Hub again with its original event ID.",
        confirm_id: "resubmit-epcis-event-#{id}-confirm",
        confirm_label: "Resubmit",
        confirm_event: "resubmit",
        confirm_id_value: id
      )

    confirm_markup(assigns)
  end

  defp confirm_markup(assigns) do
    ~H"""
    <.td_modal
      id="epcis-confirm"
      show
      title={@title}
      on_cancel={JS.push("cancel_confirm")}
    >
      <:body>
        <p class="td-note">{@body}</p>
      </:body>
      <:footer>
        <.td_button type="button" variant="secondary" label="Cancel" phx-click="cancel_confirm" />
        <.td_button
          id={@confirm_id}
          type="button"
          variant="primary"
          label={@confirm_label}
          phx-click={@confirm_event}
          phx-value-id={@confirm_id_value}
        />
      </:footer>
    </.td_modal>
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
      class={["td-menu-item", @selected_status == @status && "is-active"]}
    >
      <.td_icon name={@icon} />
      <span class="flex-1 text-left">{@label}</span>
      <span class="td-count">{@count}</span>
    </button>
    """
  end

  def format_eat(%DateTime{} = dt), do: ThamaniDawaWeb.TimeFormat.datetime(dt)

  def format_eat(%NaiveDateTime{} = dt) do
    dt
    |> DateTime.from_naive!("Etc/UTC")
    |> format_eat()
  end

  def format_eat(_), do: "—"

  def short_id(event_id) when is_binary(event_id), do: String.slice(event_id, 0, 8)
  def short_id(_), do: "—"

  def display_status("pending"), do: {"Pending", "warning"}
  def display_status(status) when status in ["accepted", "warning"], do: {"Sent", "success"}
  def display_status(status) when status in ["rejected", "dead", "blocked"], do: {"Failed", "danger"}
  def display_status(status), do: {Phoenix.Naming.humanize(status), "neutral"}

  def event_detail(%OutboxEvent{status: "blocked", blocked_reason: reason})
      when is_binary(reason) and reason != "",
      do: reason

  def event_detail(%OutboxEvent{status: "warning", response: %{"warnings" => warnings}})
      when is_list(warnings),
      do: Enum.join(warnings, ", ")

  def event_detail(%OutboxEvent{status: status, response: response})
      when status in ["rejected", "dead"] and is_map(response) do
    Map.get(response, "raw") || Map.get(response, "error") || inspect(response)
  end

  def event_detail(_), do: nil

  def event_site_name(%OutboxEvent{} = event, site_names) do
    case event_gln(event) do
      nil -> nil
      gln -> Map.get(site_names, gln)
    end
  end

  def event_gln(%OutboxEvent{payload: %{"bizLocation" => %{"id" => urn}}}) do
    case Urn.gln_from_sgln(urn) do
      {:ok, gln} -> gln
      :error -> nil
    end
  end

  def event_gln(_), do: nil

  defp business_step_label(%OutboxEvent{payload: %{"bizStep" => step}}) when is_binary(step),
    do: Phoenix.Naming.humanize(step)

  defp business_step_label(%OutboxEvent{event_type: type}) when is_binary(type),
    do: Phoenix.Naming.humanize(type)

  defp business_step_label(_), do: "Event"

  defp event_type_label(%OutboxEvent{payload: %{"type" => type}}) when is_binary(type) do
    type
    |> String.replace_suffix("Event", " event")
    |> String.replace("Event", " event")
  end

  defp event_type_label(%OutboxEvent{event_type: type}) when is_binary(type),
    do: "#{Phoenix.Naming.humanize(type)} event"

  defp event_type_label(_), do: "Event"

  defp identifiers(%OutboxEvent{payload: payload}) when is_map(payload) do
    List.wrap(payload["epcList"]) ++ List.wrap(payload["parentID"])
  end

  defp identifiers(_), do: []

  defp batch_of(%OutboxEvent{payload: payload}) when is_map(payload) do
    get_in(payload, ["ilmd", "lotNumber"]) || payload["batch"] || payload["lotNumber"]
  end

  defp batch_of(_), do: nil

  defp disposition_of(%OutboxEvent{payload: %{"disposition" => disp}}) when is_binary(disp), do: disp
  defp disposition_of(_), do: nil

  defp total_events(counts), do: counts |> Map.values() |> Enum.sum()

  defp selected_filter_label("all"), do: "All events"
  defp selected_filter_label(status), do: String.capitalize(status)
end
