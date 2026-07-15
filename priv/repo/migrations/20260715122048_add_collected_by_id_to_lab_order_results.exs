defmodule ThamaniDawa.Repo.Migrations.AddCollectedByIdToLabOrderResults do
  use Ecto.Migration

  def change do
    alter table(:lab_order_results) do
      add :collected_by_id, references(:users, on_delete: :nilify_all)
    end
  end
end
