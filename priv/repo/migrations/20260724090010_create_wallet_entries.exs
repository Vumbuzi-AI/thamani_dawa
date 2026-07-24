defmodule ThamaniDawa.Repo.Migrations.CreateWalletEntries do
  use Ecto.Migration

  def change do
    create table(:wallet_entries) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :site_id, references(:sites, on_delete: :restrict), null: false
      add :payment_id, references(:payments, on_delete: :restrict), null: false

      add :amount, :decimal, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:wallet_entries, [:organization_id])
    create index(:wallet_entries, [:site_id])
    create unique_index(:wallet_entries, [:payment_id])
  end
end
