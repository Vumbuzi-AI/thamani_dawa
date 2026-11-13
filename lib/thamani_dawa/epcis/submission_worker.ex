defmodule ThamaniDawa.Epcis.SubmissionWorker do
  @moduledoc """
  Oban worker that drains one organization's EPCIS outbox in strict
  `occurred_at` order (docs/PPB_TNT_INTEGRATION.md §4.2). One unique job per
  organization; a retrying head event snoozes the whole queue, a
  hard-rejected or dead event halts it until a human resubmits.
  """

  use Oban.Worker,
    queue: :epcis,
    max_attempts: 1,
    unique: [
      period: 60,
      keys: [:organization_id],
      states: [:available, :scheduled]
    ]

  alias ThamaniDawa.Epcis.Client
  alias ThamaniDawa.Epcis.Outbox

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_id" => organization_id}}) do
    cond do
      not Client.enabled?() -> :ok
      Outbox.halted?(organization_id) -> :ok
      true -> drain(Outbox.pending_for_organization(organization_id))
    end
  end

  defp drain([]), do: :ok

  defp drain([event | rest]) do
    case wait_seconds(event) do
      0 -> submit(event, rest)
      seconds -> {:snooze, seconds}
    end
  end

  defp submit(event, rest) do
    case Client.submit(event.payload) do
      {:accepted, status, body} ->
        Outbox.mark_accepted(event, status, body)
        drain(rest)

      {:duplicate, status, body} ->
        Outbox.mark_accepted(event, status, body)
        drain(rest)

      {:rejected, status, body} ->
        Outbox.mark_rejected(event, status, body)
        :ok

      {:retry, reason} ->
        updated = Outbox.mark_retry(event, reason)

        case updated.status do
          "pending" -> {:snooze, max(wait_seconds(updated), 1)}
          _dead -> :ok
        end
    end
  end

  defp wait_seconds(%{next_attempt_at: nil}), do: 0

  defp wait_seconds(%{next_attempt_at: at}) do
    max(DateTime.diff(at, DateTime.utc_now()), 0)
  end
end
