defmodule ThamaniDawa.Repo.Migrations.CreateEpcisOutboxEvents do
  use Ecto.Migration

  def change do
    create table(:epcis_outbox_events) do
      add :organization_id, references(:organizations, on_delete: :restrict), null: false
      add :event_id, :uuid, null: false
      add :event_type, :string, null: false
      add :participant_tier, :string, null: false
      add :payload, :map, null: false
      add :occurred_at, :utc_datetime, null: false
      add :status, :string, null: false, default: "pending"
      add :http_status, :integer
      add :response, :map
      add :blocked_reason, :string
      add :attempts, :integer, null: false, default: 0
      add :next_attempt_at, :utc_datetime
      add :source_type, :string
      add :source_id, :bigint

      timestamps(type: :utc_datetime)
    end

    create unique_index(:epcis_outbox_events, [:event_id])
    create index(:epcis_outbox_events, [:organization_id, :status, :occurred_at, :id])
    create index(:epcis_outbox_events, [:source_type, :source_id])
  end
end
