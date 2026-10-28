defmodule ThamaniDawa.Repo.Migrations.AddSpecimenIdToLabConsumableUsage do
  use Ecto.Migration

  def change do
    alter table(:lab_consumable_usage) do
      add :specimen_id, references(:lab_specimens, on_delete: :nilify_all)
    end

    create index(:lab_consumable_usage, [:specimen_id])
  end
end
