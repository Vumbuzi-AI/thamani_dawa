defmodule ThamaniDawa.Repo.Migrations.CreateLabConsumableUsage do
  use Ecto.Migration

  def change do
    create table(:lab_consumable_usage) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :lab_order_id, references(:lab_orders, on_delete: :nilify_all)
      add :batch_id, references(:batches, on_delete: :delete_all), null: false
      add :quantity, :integer, null: false
      add :used_by_id, references(:users, on_delete: :nilify_all)
      add :purpose, :string
      add :used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:lab_consumable_usage, [:organization_id])
    create index(:lab_consumable_usage, [:lab_order_id])
    create index(:lab_consumable_usage, [:batch_id])
    create index(:lab_consumable_usage, [:used_by_id])
  end
end
