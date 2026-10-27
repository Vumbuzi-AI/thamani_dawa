defmodule ThamaniDawa.Repo.Migrations.AddQuantityAllocatedToDistributorOrderItems do
  use Ecto.Migration

  def change do
    alter table(:distributor_order_items) do
      add :quantity_allocated, :integer, default: 0, null: false
    end
  end
end
