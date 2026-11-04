defmodule ThamaniDawa.Repo.Migrations.AddInventoryTypeToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :inventory_type, :string, null: false, default: "medicine"
    end

    create index(:products, [:organization_id, :inventory_type])
  end
end
