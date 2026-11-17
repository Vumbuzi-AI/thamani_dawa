defmodule ThamaniDawa.Repo.Migrations.CreateApiIdempotencyKeys do
  use Ecto.Migration

  def change do
    create table(:api_idempotency_keys) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :body_hash, :binary, null: false
      add :status, :integer, null: false
      add :body, :map, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:api_idempotency_keys, [:user_id, :key])
  end
end
