defmodule ThamaniDawa.Epcis.OutboxEvent do
  @moduledoc """
  One EPCIS event awaiting (or past) submission to the PPB Track & Trace Hub.

  Rows are written in the same transaction as the business action that caused
  them, then drained per-organization in `occurred_at` order by
  `ThamaniDawa.Epcis.SubmissionWorker`. The `event_id` is the EPCIS eventID —
  the Hub's idempotency key — so retries always resend the same identity.
  The one deliberate same-event_id duplicate is an error declaration
  (`Epcis.declare_error/3`), which re-declares a stored event as a fresh row
  so the original keeps its audit trail.

  Statuses:

    * `"pending"` — queued, not yet accepted by the Hub
    * `"blocked"` — cannot be built/sent (e.g. missing partner GLN); human
      action needed, reason in `blocked_reason`
    * `"accepted"` — stored by the Hub (HTTP 201/202, or 409 duplicate)
    * `"warning"` — stored by the Hub with `warnings[]` (kept in `response`)
    * `"rejected"` — hard reject (HTTP 400); never auto-retried
    * `"dead"` — retry budget exhausted on transient errors
  """

  use Ecto.Schema

  @statuses ~w(pending blocked accepted warning rejected dead)
  @tiers ~w(distributor facility)

  schema "epcis_outbox_events" do
    field :event_id, Ecto.UUID
    field :event_type, :string
    field :participant_tier, :string
    field :payload, :map
    field :occurred_at, :utc_datetime
    field :status, :string, default: "pending"
    field :http_status, :integer
    field :response, :map
    field :blocked_reason, :string
    field :attempts, :integer, default: 0
    field :next_attempt_at, :utc_datetime
    field :source_type, :string
    field :source_id, :integer

    belongs_to :organization, ThamaniDawa.Organizations.Organization

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def tiers, do: @tiers
end
