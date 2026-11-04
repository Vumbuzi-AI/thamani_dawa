defmodule ThamaniDawa.Repo.Migrations.CreateScanEvents do
  use Ecto.Migration

  def change do
    create table(:scan_events) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :gtin, :string, null: false
      add :batch_no, :string
      add :gln, :string
      add :event_type, :string, null: false
      add :reference_id, :integer
      add :user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:scan_events, [:organization_id])
    create index(:scan_events, [:gtin, :batch_no])
    create index(:scan_events, [:event_type])
  end
end
