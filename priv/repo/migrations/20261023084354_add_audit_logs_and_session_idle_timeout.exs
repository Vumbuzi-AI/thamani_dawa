defmodule ThamaniDawa.Repo.Migrations.AddAuditLogsAndSessionIdleTimeout do
  use Ecto.Migration

  def change do
    alter table(:users_tokens) do
      add :last_used_at, :utc_datetime
    end

    execute "UPDATE users_tokens SET last_used_at = inserted_at WHERE context = 'session'"

    create index(:users_tokens, [:context, :last_used_at])

    create table(:audit_logs) do
      add :user_id, references(:users, on_delete: :nilify_all)
      add :organization_id, references(:organizations, on_delete: :nilify_all)
      add :action, :string, null: false
      add :table_name, :string, null: false
      add :record_id, :integer, null: false
      add :previous_state, :map
      add :new_state, :map
      add :changed_fields, {:array, :string}, null: false, default: []

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:audit_logs, [:organization_id, :inserted_at])
    create index(:audit_logs, [:table_name, :record_id])
    create index(:audit_logs, [:user_id, :inserted_at])
  end
end
