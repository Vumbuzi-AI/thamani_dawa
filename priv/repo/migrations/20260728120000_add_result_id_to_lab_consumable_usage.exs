defmodule ThamaniDawa.Repo.Migrations.AddResultIdToLabConsumableUsage do
  use Ecto.Migration

  def change do
    alter table(:lab_consumable_usage) do
      add :lab_order_result_id,
          references(:lab_order_results, on_delete: :nilify_all),
          null: true
    end

    create index(:lab_consumable_usage, [:lab_order_result_id])
  end
end
