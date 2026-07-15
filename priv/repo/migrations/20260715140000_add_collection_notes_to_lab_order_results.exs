defmodule ThamaniDawa.Repo.Migrations.AddCollectionNotesToLabOrderResults do
  use Ecto.Migration

  def change do
    alter table(:lab_order_results) do
      add :collection_notes, :text
    end
  end
end
