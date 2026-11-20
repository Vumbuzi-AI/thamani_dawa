defmodule ThamaniDawa.Repo.Migrations.CreateRecallHolders do
  use Ecto.Migration

  def change do
    create table(:recall_holders) do
      add :recall_id, references(:recalls, on_delete: :delete_all), null: false
      add :organization_id, references(:organizations, on_delete: :restrict), null: false
      add :batch_id, references(:batches, on_delete: :restrict), null: false
      add :quantity_at_recall, :integer, null: false
      add :acknowledged_at, :utc_datetime
      add :acknowledged_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:recall_holders, [:recall_id, :batch_id])
    create index(:recall_holders, [:organization_id])
    create index(:recall_holders, [:recall_id])
  end
end
