defmodule ThamaniDawa.Repo.Migrations.AddStockSerializationEnabledToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :stock_serialization_enabled, :boolean, default: false, null: false
    end
  end
end
