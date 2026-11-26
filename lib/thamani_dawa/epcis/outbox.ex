defmodule ThamaniDawa.Epcis.Outbox do
  @moduledoc """
  Transactional outbox for EPCIS events (docs/PPB_TNT_INTEGRATION.md §4.2).

  `enqueue/1` must be called inside the caller's `Repo.transaction` so an
  event exists if and only if the business action committed. Enqueueing also
  inserts (or refreshes) the per-organization Oban submission job.
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.Epcis.OutboxEvent
  alias ThamaniDawa.Epcis.SubmissionWorker
  alias ThamaniDawa.Repo

  @max_attempts 50

  def enqueue(attrs) when is_map(attrs) do
    event =
      Repo.insert!(%OutboxEvent{
        organization_id: Map.fetch!(attrs, :organization_id),
        event_id: Map.get_lazy(attrs, :event_id, &Ecto.UUID.generate/0),
        event_type: Map.fetch!(attrs, :event_type),
        participant_tier: Map.fetch!(attrs, :participant_tier),
        payload: Map.fetch!(attrs, :payload),
        occurred_at: Map.fetch!(attrs, :occurred_at),
        status: Map.get(attrs, :status, "pending"),
        blocked_reason: Map.get(attrs, :blocked_reason),
        source_type: Map.get(attrs, :source_type),
        source_id: Map.get(attrs, :source_id)
      })

    if event.status == "pending" do
      %{organization_id: event.organization_id, forced: false}
      |> SubmissionWorker.new()
      |> Oban.insert!()
    end

    event
  end

  def block(attrs, reason) when is_map(attrs) and is_binary(reason) do
    attrs
    |> Map.merge(%{status: "blocked", blocked_reason: reason})
    |> enqueue()
  end

  @doc """
  Pending events for one organization, oldest first — the exact submission
  order. The worker never skips a not-yet-due head event; it snoozes, so a
  retrying event head-blocks everything behind it by design.
  """
  def pending_for_organization(organization_id) do
    Repo.all(
      from e in OutboxEvent,
        where: e.organization_id == ^organization_id and e.status == "pending",
        order_by: [asc: e.occurred_at, asc: e.id]
    )
  end

  @doc """
  Whether the organization's queue is halted by a hard-rejected or dead
  event. Submitting past one would break chronological order, so the worker
  sends nothing until it is resolved via `resubmit/1`.
  """
  def halted?(organization_id) do
    Repo.exists?(
      from e in OutboxEvent,
        where: e.organization_id == ^organization_id and e.status in ["rejected", "dead"]
    )
  end

  @doc "The prerequisite EPCIS events that must be accepted before this event can be submitted."
  def unsatisfied_dependencies(
        %OutboxEvent{event_type: "packing", source_type: "manufacturer_shipper_sscc"} = event
      ) do
    batch_ids =
      Repo.all(
        from s in ThamaniDawa.Manufacturing.Serial,
          where: s.manufacturer_shipper_sscc_id == ^event.source_id,
          select: s.manufacturer_batch_id,
          distinct: true
      )

    batches =
      Repo.all(
        from b in ThamaniDawa.Manufacturing.Batch,
          where: b.id in ^batch_ids,
          select: %{id: b.id, identifier: b.batch_no}
      )

    dependencies_for_sources(event, "commissioning", "manufacturer_batch", batches, "batch")
  end

  def unsatisfied_dependencies(
        %OutboxEvent{event_type: "pallet_packing", source_type: "manufacturer_pallet"} = event
      ) do
    shippers =
      Repo.all(
        from s in ThamaniDawa.Manufacturing.ShipperSscc,
          where: s.manufacturer_pallet_id == ^event.source_id,
          select: %{id: s.id, identifier: s.code}
      )

    # A manually supplied shipper can already exist in GS1 without a local
    # packing event. Only shippers with a local event need to wait for it.
    event
    |> dependencies_for_sources(
      "packing",
      "manufacturer_shipper_sscc",
      shippers,
      "shipper SSCC"
    )
    |> Enum.reject(&(&1.status == "missing"))
  end

  def unsatisfied_dependencies(_event), do: []

  @doc "Whether a manufacturer aggregation event may be submitted to TrackIQ."
  def dependencies_satisfied?(event), do: unsatisfied_dependencies(event) == []

  defp dependencies_for_sources(event, event_type, source_type, sources, source_label) do
    source_ids = Enum.map(sources, & &1.id)

    events =
      Repo.all(
        from e in OutboxEvent,
          where: e.organization_id == ^event.organization_id,
          where: e.event_type == ^event_type and e.source_type == ^source_type,
          where: e.source_id in ^source_ids,
          order_by: [desc: e.occurred_at, desc: e.id]
      )
      |> Enum.group_by(& &1.source_id)

    sources
    |> Enum.flat_map(fn source ->
      source_events = Map.get(events, source.id, [])

      if Enum.any?(source_events, &(&1.status in ["accepted", "warning"])) do
        []
      else
        latest = List.first(source_events)

        [
          %{
            event_type: event_type,
            event_id: latest && latest.event_id,
            source_label: source_label,
            source_identifier: source.identifier,
            status: if(latest, do: latest.status, else: "missing")
          }
        ]
      end
    end)
    |> then(fn
      [] when sources == [] ->
        [
          %{
            event_type: event_type,
            event_id: nil,
            source_label: source_label,
            source_identifier: "unknown",
            status: "missing"
          }
        ]

      dependencies ->
        dependencies
    end)
  end

  def mark_accepted(%OutboxEvent{} = event, http_status, response) do
    status = if warnings?(response), do: "warning", else: "accepted"
    update!(event, status: status, http_status: http_status, response: response)
  end

  def mark_rejected(%OutboxEvent{} = event, http_status, response) do
    update!(event, status: "rejected", http_status: http_status, response: response)
  end

  @doc """
  Returns a pending event to `blocked` because the organization has no API
  key configured for the event's tier — never submitted, unlike `rejected`
  (which the Hub itself turned down). Fixed the same way as a build-time
  `block/2`: add the key, then `resubmit/1`.
  """
  def mark_blocked(%OutboxEvent{} = event, reason) do
    update!(event, status: "blocked", blocked_reason: reason)
  end

  def mark_retry(%OutboxEvent{} = event, reason) do
    attempts = event.attempts + 1

    if attempts >= @max_attempts do
      update!(event,
        status: "dead",
        attempts: attempts,
        response: %{"error" => inspect(reason)}
      )
    else
      update!(event,
        attempts: attempts,
        next_attempt_at:
          DateTime.utc_now()
          |> DateTime.add(backoff_seconds(attempts))
          |> DateTime.truncate(:second),
        response: %{"error" => inspect(reason)}
      )
    end
  end

  @doc "Returns a rejected, dead, or blocked event to the pending queue, keeping its event_id."
  def resubmit(%OutboxEvent{status: status} = event)
      when status in ["rejected", "dead", "blocked"] do
    event =
      update!(event,
        status: "pending",
        blocked_reason: nil,
        next_attempt_at: nil,
        attempts: 0
      )

    SubmissionWorker.enqueue_now(event.organization_id)
    event
  end

  @doc """
  Removes an event the Hub never stored, so later events can be sent.

  A hard rejection (400) and a locally blocked event both happen before PPB
  records anything, so no error declaration is needed — discarding is the
  honest resolution when the payload is wrong and cannot be edited here.
  `dead` is deliberately excluded: those events exhausted retries after a
  transient failure and may have reached the Hub.

  The worker's job completed when it hit the halt, so a forced drain is
  enqueued to pick up anything still pending after the delete.
  """
  def discard(%OutboxEvent{status: status} = event) when status in ["rejected", "blocked"] do
    organization_id = event.organization_id

    case Repo.delete(event) do
      {:ok, deleted} ->
        SubmissionWorker.enqueue_now(organization_id)
        {:ok, deleted}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def discard(%OutboxEvent{}), do: {:error, :not_discardable}

  @doc "Fetches one outbox event scoped to the organization. Raises if not found."
  def get_event!(organization_id, id) do
    Repo.get_by!(OutboxEvent, id: id, organization_id: organization_id)
  end

  @doc """
  Count of outbox events per status for an organization — the admin view's
  summary chips. Pass `:tier` to scope to one participant tier (e.g. the
  manufacturer portal's own queue, distinct from distributor/facility
  events reported by the same organization).
  """
  def count_by_status(organization_id, opts \\ []) do
    counts =
      Repo.all(
        from e in OutboxEvent,
          where: e.organization_id == ^organization_id,
          where: ^tier_filter(opts),
          group_by: e.status,
          select: {e.status, count(e.id)}
      )

    Map.new(counts)
  end

  def list_events(organization_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Repo.all(
      from e in OutboxEvent,
        where: e.organization_id == ^organization_id,
        where: ^tier_filter(opts),
        order_by: [desc: e.occurred_at, desc: e.id],
        limit: ^limit
    )
  end

  defp tier_filter(opts) do
    case Keyword.get(opts, :tier) do
      nil -> dynamic(true)
      tier -> dynamic([e], e.participant_tier == ^tier)
    end
  end

  @doc """
  Events reported for one source record (e.g. a `Batch`'s status-change
  history), oldest first — for the batch trail view.
  """
  def list_events_for_source(organization_id, source_type, source_id)
      when is_binary(source_type) and is_integer(source_id) do
    Repo.all(
      from e in OutboxEvent,
        where: e.organization_id == ^organization_id,
        where: e.source_type == ^source_type,
        where: e.source_id == ^source_id,
        order_by: [asc: e.occurred_at, asc: e.id]
    )
  end

  defp update!(event, changes) do
    event
    |> Ecto.Changeset.change(changes)
    |> Repo.update!()
  end

  defp warnings?(%{"warnings" => [_ | _]}), do: true
  defp warnings?(_response), do: false

  defp backoff_seconds(attempts), do: min(30 * Integer.pow(2, attempts - 1), 3600)
end
