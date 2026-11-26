defmodule ThamaniDawaWeb.ManufacturerEpcisLive do
  use ThamaniDawaWeb, :live_view

  import ThamaniDawaWeb.EpcisReporting, only: [epcis_body: 1, epcis_search: 1]

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Epcis.Client
  alias ThamaniDawa.Epcis.Outbox
  alias ThamaniDawa.Epcis.OutboxEvent
  alias ThamaniDawa.Epcis.SubmissionWorker
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
     |> assign(:confirm_action, nil)
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

    tab =
      cond do
        params["tab"] == "diagnostics" -> :diagnostics
        event.status in ["rejected", "dead"] -> :response
        true -> :request
      end

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
        socket = reload(socket) |> assign(:confirm_action, nil)

        {:noreply,
         put_flash(
           socket,
           :info,
           "Event #{short_id(event.event_id)} is ready to send again. It keeps the same reference."
         )}

      _ ->
        {:noreply,
         put_flash(socket, :error, "Only rejected, dead, or blocked events can be resubmitted.")}
    end
  end

  def handle_event("discard", %{"id" => id}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    event = Outbox.get_event!(organization_id, id)

    case Outbox.discard(event) do
      {:ok, _event} ->
        {:noreply,
         socket
         |> reload()
         |> assign(:confirm_action, nil)
         |> put_flash(
           :info,
           "Event #{short_id(event.event_id)} discarded. Pending events can send again."
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Only rejected or blocked events can be discarded.")}
    end
  end

  def handle_event("send_event", %{"id" => id}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    event = Outbox.get_event!(organization_id, id)

    cond do
      not Organizations.epcis_api_key_configured?(
        socket.assigns.organization,
        event.participant_tier
      ) ->
        {:noreply, put_flash(socket, :error, missing_key_message())}

      event.status == "pending" ->
        case SubmissionWorker.submit_now(event) do
          {status, _updated} when status in [:accepted, :duplicate] ->
            {:noreply,
             socket
             |> reload()
             |> assign(:confirm_action, nil)
             |> put_flash(:info, "Event #{short_id(event.event_id)} sent to PPB.")}

          {:rejected, _updated} ->
            {:noreply,
             socket
             |> reload()
             |> assign(:confirm_action, nil)
             |> put_flash(:error, "PPB rejected event #{short_id(event.event_id)}.")}

          {:retry, _updated} ->
            {:noreply,
             socket
             |> reload()
             |> assign(:confirm_action, nil)
             |> put_flash(
               :error,
               "Couldn't reach PPB for event #{short_id(event.event_id)} — it will retry automatically."
             )}

          {:blocked, _updated} ->
            {:noreply,
             socket
             |> reload()
             |> assign(:confirm_action, nil)
             |> put_flash(
               :error,
               "The key for this reporting event is missing. Add it on API keys, then send this event again."
             )}
        end

      true ->
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

    cond do
      socket.assigns.tnt_keys_missing? ->
        {:noreply, put_flash(socket, :error, missing_key_message())}

      pending > 0 ->
        SubmissionWorker.enqueue_now(organization_id)

        {:noreply,
         socket
         |> reload()
         |> assign(:confirm_action, nil)
         |> put_flash(
           :info,
           "Sending #{pending} pending event#{if pending == 1, do: "", else: "s"} to PPB now."
         )}

      true ->
        {:noreply, put_flash(socket, :error, "There are no pending events to send.")}
    end
  end

  def handle_event("prompt_send_now", _params, socket),
    do: {:noreply, assign(socket, :confirm_action, :send_now)}

  def handle_event("prompt_send_event", %{"id" => id}, socket),
    do: {:noreply, assign(socket, :confirm_action, {:send_event, id})}

  def handle_event("prompt_resubmit", %{"id" => id}, socket),
    do: {:noreply, assign(socket, :confirm_action, {:resubmit, id})}

  def handle_event("prompt_discard", %{"id" => id}, socket),
    do: {:noreply, assign(socket, :confirm_action, {:discard, id})}

  def handle_event("cancel_confirm", _params, socket),
    do: {:noreply, assign(socket, :confirm_action, nil)}

  defp missing_key_message,
    do: "Add your PPB TNT API key before sending EPCIS events."

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

  defp short_id(event_id), do: String.slice(event_id, -8, 8)

  def render(%{epcis_portal: :organization} = assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path={@epcis_path}>
      <:search>
        <.epcis_search search_query={@search_query} />
      </:search>
      <.epcis_body
        empty_copy="Generate serials or create an SSCC and its events will appear here."
        organization={@organization}
        status_counts={@status_counts}
        selected_status={@selected_status}
        search_query={@search_query}
        submission_enabled?={@submission_enabled?}
        queue_halted?={@queue_halted?}
        tnt_keys_missing?={@tnt_keys_missing?}
        api_keys_path={@api_keys_path}
        streams={@streams}
        site_names={@site_names}
        inspecting_event={@inspecting_event}
        inspection_tab={@inspection_tab}
        confirm_action={@confirm_action}
      />
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
      <:search>
        <.epcis_search search_query={@search_query} />
      </:search>
      <.epcis_body
        empty_copy="Generate serials or create an SSCC and its events will appear here."
        organization={@organization}
        status_counts={@status_counts}
        selected_status={@selected_status}
        search_query={@search_query}
        submission_enabled?={@submission_enabled?}
        queue_halted?={@queue_halted?}
        tnt_keys_missing?={@tnt_keys_missing?}
        api_keys_path={@api_keys_path}
        streams={@streams}
        site_names={@site_names}
        inspecting_event={@inspecting_event}
        inspection_tab={@inspection_tab}
        confirm_action={@confirm_action}
      />
    </Layouts.manufacturer_shell>
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
end
