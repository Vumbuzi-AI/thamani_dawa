defmodule ThamaniDawa.Repo.Migrations.RelaxEpcisOutboxEventIdIndex do
  use Ecto.Migration

  def change do
    # Error declarations (docs/PPB_TNT_INTEGRATION.md §7) resubmit a stored
    # event under its original eventID — the one legal same-eventID capture —
    # as a fresh outbox row so the original submission keeps its audit trail.
    # That requires event_id uniqueness to become a plain lookup index.
    drop_if_exists(unique_index(:epcis_outbox_events, [:event_id]))
    create_if_not_exists(index(:epcis_outbox_events, [:event_id]))
  end
end
