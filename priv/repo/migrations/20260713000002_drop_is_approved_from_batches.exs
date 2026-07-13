defmodule ThamaniDawa.Repo.Migrations.DropIsApprovedFromBatches do
  use Ecto.Migration

  def change do
    alter table(:batches) do
      remove :is_approved, :boolean, default: false, null: false
    end
  end
end
