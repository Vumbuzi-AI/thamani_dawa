defmodule ThamaniDawa.Repo.Migrations.AddAllocationProcessedToDistributorOrderItems do
  use Ecto.Migration

  def change do
    alter table(:distributor_order_items) do
      add :allocation_processed, :boolean, null: false, default: false
    end
  end
end
