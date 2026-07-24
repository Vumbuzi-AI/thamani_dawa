defmodule ThamaniDawa.Repo.Migrations.CreateStockTakeEntries do
  use Ecto.Migration

  def change do
    create table(:stock_take_entries) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :stock_take_id, references(:stock_takes, on_delete: :delete_all), null: false
      add :batch_id, references(:batches, on_delete: :delete_all), null: false
      add :expected_quantity, :integer, null: false
      add :counted_quantity, :integer
      add :variance, :integer
      add :has_been_applied, :boolean, null: false, default: false
      add :notes, :text
      add :counted_by_id, references(:users, on_delete: :nilify_all)
      add :counted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:stock_take_entries, [:organization_id])
    create index(:stock_take_entries, [:batch_id])
    create index(:stock_take_entries, [:counted_by_id])
    create unique_index(:stock_take_entries, [:stock_take_id, :batch_id])
  end
end
