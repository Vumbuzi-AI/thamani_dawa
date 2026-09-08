defmodule ThamaniDawa.Repo.Migrations.CreateGs1Requests do
  use Ecto.Migration

  def change do
    create table(:gs1_requests) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)

      add :endpoint, :string, null: false
      # Client-generated idempotency key, written before the call goes out so a
      # crashed request is always recoverable (serialisation.md §4.5).
      add :request_id, :string, null: false
      add :payload_digest, :string, null: false

      add :status, :string, null: false, default: "pending"
      add :response_summary, :map, null: false, default: %{}
      add :error_message, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:gs1_requests, [:request_id])
    create index(:gs1_requests, [:organization_id, :inserted_at])
    create index(:gs1_requests, [:status])
  end
end
