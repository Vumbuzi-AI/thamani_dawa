defmodule ThamaniDawa.Repo.Migrations.CreateScanEvents do
  use Ecto.Migration

  def change do
    create table(:scan_events) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :gtin, :string, null: false
      add :batch_no, :string, null: false
      add :gln, :string
      add :event_type, :string, null: false
      add :reference_id, :bigint
      add :user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:scan_events, [:organization_id])
    create index(:scan_events, [:reference_id])
    create index(:scan_events, [:user_id])
    create index(:scan_events, [:event_type])
  end
end
