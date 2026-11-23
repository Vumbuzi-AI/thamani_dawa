defmodule ThamaniDawa.Epcis.SubmissionWorker do
  @moduledoc """
  Oban worker that drains one organization's EPCIS outbox in strict
  `occurred_at` order (docs/PPB_TNT_INTEGRATION.md §4.2). One unique job per
  (organization, forced?) pair; a retrying head event snoozes the whole
  queue, a hard-rejected or dead event halts it until a human resubmits.

  An org whose `epcis_submission_mode` is `:manual` skips draining when the
  job was enqueued automatically (i.e. not `forced`) — events still land in
  the outbox as `pending`, they just sit there until an explicit trigger.
  `enqueue_now/1` is that trigger: it's what the "send now" admin action and
  `Outbox.resubmit/1` use, and it always drains regardless of mode, since
  both are a human explicitly asking for this to go out right now.
  """

  use Oban.Worker,
    queue: :epcis,
    max_attempts: 1,
    unique: [
      period: 60,
      keys: [:organization_id, :forced],
      states: [:available, :scheduled]
    ]

  alias ThamaniDawa.Epcis.Client
  alias ThamaniDawa.Epcis.Outbox
  alias ThamaniDawa.Epcis.OutboxEvent
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Organizations.Organization

  @doc "Enqueues a forced drain for an organization — runs regardless of its submission mode."
  def enqueue_now(organization_id) do
    %{organization_id: organization_id, forced: true}
    |> new()
    |> Oban.insert!()
  end

  @doc """
  Submits one pending event directly to PPB, independent of its position in
  the outbox queue. Unlike `enqueue_now/1`, this does not drain in
  `occurred_at` order — it's the per-event "send now" admin action, a
  deliberate, operator-requested exception to the usual ordering guarantee.
  """
  def submit_now(%OutboxEvent{status: "pending"} = event) do
    organization = Organizations.get_organization!(event.organization_id)
    submit_event(event, organization)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_id" => organization_id} = args}) do
    forced? = Map.get(args, "forced", false)
    organization = Organizations.get_organization!(organization_id)

    cond do
      not Client.enabled?() -> :ok
      Outbox.halted?(organization_id) -> :ok
      not forced? and organization.epcis_submission_mode == :manual -> :ok
      true -> drain(Outbox.pending_for_organization(organization_id), organization)
    end
  end

  defp drain([], _organization), do: :ok

  defp drain([event | rest], organization) do
    case wait_seconds(event) do
      0 -> submit(event, rest, organization)
      seconds -> {:snooze, seconds}
    end
  end

  defp submit(event, rest, organization) do
    case submit_event(event, organization) do
      {:accepted, _updated} ->
        drain(rest, organization)

      {:duplicate, _updated} ->
        drain(rest, organization)

      {:rejected, _updated} ->
        :ok

      {:blocked, _updated} ->
        drain(rest, organization)

      {:retry, updated} ->
        case updated.status do
          "pending" -> {:snooze, max(wait_seconds(updated), 1)}
          _dead -> :ok
        end
    end
  end

  defp submit_event(event, organization) do
    api_key_override = api_key_override(organization, event.participant_tier)

    case Client.submit(event.payload, event.participant_tier, api_key_override) do
      {:accepted, status, body} -> {:accepted, Outbox.mark_accepted(event, status, body)}
      {:duplicate, status, body} -> {:duplicate, Outbox.mark_accepted(event, status, body)}
      {:rejected, status, body} -> {:rejected, Outbox.mark_rejected(event, status, body)}
      {:retry, reason} -> {:retry, Outbox.mark_retry(event, reason)}
      {:blocked, reason} -> {:blocked, Outbox.mark_blocked(event, reason)}
    end
  end

  defp api_key_override(%Organization{} = organization, "distributor"),
    do: organization.epcis_distributor_api_key

  defp api_key_override(%Organization{} = organization, "manufacturer"),
    do: organization.epcis_manufacturer_api_key

  defp api_key_override(%Organization{} = organization, _tier),
    do: organization.epcis_facility_api_key

  defp wait_seconds(%{next_attempt_at: nil}), do: 0

  defp wait_seconds(%{next_attempt_at: at}) do
    max(DateTime.diff(at, DateTime.utc_now()), 0)
  end
end
