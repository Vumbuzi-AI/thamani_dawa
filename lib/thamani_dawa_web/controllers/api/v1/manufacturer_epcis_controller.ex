defmodule ThamaniDawaWeb.Api.V1.ManufacturerEpcisController do
  @moduledoc """
  Read-only view of the manufacturer's TNT (EPCIS) reporting queue, as on
  the web's TNT reporting page: the queue's status, and its events with
  why any of them are stuck. Resending, resubmitting and switching the
  submission mode stay on the web.
  """

  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Epcis.Client
  alias ThamaniDawa.Epcis.Outbox
  alias ThamaniDawa.Organizations
  alias ThamaniDawaWeb.Api.Params
  alias ThamaniDawaWeb.Api.Response
  alias ThamaniDawaWeb.Api.Serializer
  alias ThamaniDawaWeb.Api.V1.Helpers
  alias ThamaniDawaWeb.Api.V1.ManufacturerFallback
  alias ThamaniDawaWeb.Plugs.RequirePortal

  import Helpers

  action_fallback ManufacturerFallback

  plug RequirePortal, :manufacturer

  @tier "manufacturer"
  @statuses ~w(pending warning blocked rejected dead accepted)

  def status(conn, _params) do
    organization = Organizations.get_organization!(org_id(conn))

    Response.data(conn, %{
      status_counts: Outbox.status_summary(organization.id, tier: @tier),
      queue_halted: Outbox.halted?(organization.id),
      submission_enabled: Client.enabled?(),
      submission_mode: organization.epcis_submission_mode,
      api_key_configured: organization.epcis_manufacturer_api_key_last4 not in [nil, ""]
    })
  end

  # The newest 200 events, like the web page, filtered by status and by a
  # search on the event type or id.
  def events(conn, params) do
    {page, per_page} = Params.page(params)

    events =
      conn
      |> org_id()
      |> Outbox.list_events(limit: 200, tier: @tier)
      |> filter_status(params["status"])
      |> filter_search(params["search"])

    {entries, meta} = Params.slice(events, page, per_page)
    Response.page(conn, Enum.map(entries, &Serializer.outbox_event/1), meta)
  end

  def event(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         {:ok, event} <- fetch(fn -> Outbox.get_event!(org_id(conn), id) end),
         :ok <- manufacturer_event(event) do
      Response.data(conn, Serializer.outbox_event(event, payload: true))
    end
  end

  defp manufacturer_event(%{participant_tier: @tier}), do: :ok
  defp manufacturer_event(_event), do: {:error, :not_found}

  defp filter_status(events, status) when status in @statuses,
    do: Enum.filter(events, &(&1.status == status))

  defp filter_status(events, _status), do: events

  defp filter_search(events, query) when is_binary(query) do
    case query |> String.trim() |> String.downcase() do
      "" ->
        events

      query ->
        Enum.filter(events, fn event ->
          String.contains?(String.downcase(event.event_type), query) or
            String.contains?(String.downcase(event.event_id), query)
        end)
    end
  end

  defp filter_search(events, _query), do: events
end
