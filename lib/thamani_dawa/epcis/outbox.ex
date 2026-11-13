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
      %{organization_id: event.organization_id}
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

  def mark_accepted(%OutboxEvent{} = event, http_status, response) do
    status = if warnings?(response), do: "warning", else: "accepted"
    update!(event, status: status, http_status: http_status, response: response)
  end

  def mark_rejected(%OutboxEvent{} = event, http_status, response) do
    update!(event, status: "rejected", http_status: http_status, response: response)
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

  @doc "Returns a rejected or dead event to the pending queue, keeping its event_id."
  def resubmit(%OutboxEvent{status: status} = event) when status in ["rejected", "dead"] do
    event = update!(event, status: "pending", next_attempt_at: nil, attempts: 0)

    %{organization_id: event.organization_id}
    |> SubmissionWorker.new()
    |> Oban.insert!()

    event
  end

  @doc "Fetches one outbox event scoped to the organization. Raises if not found."
  def get_event!(organization_id, id) do
    Repo.get_by!(OutboxEvent, id: id, organization_id: organization_id)
  end

  @doc "Count of outbox events per status for an organization — the admin view's summary chips."
  def count_by_status(organization_id) do
    counts =
      Repo.all(
        from e in OutboxEvent,
          where: e.organization_id == ^organization_id,
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
        order_by: [desc: e.occurred_at, desc: e.id],
        limit: ^limit
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
