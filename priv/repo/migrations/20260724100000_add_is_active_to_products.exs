defmodule ThamaniDawa.Repo.Migrations.AddIsActiveToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :is_active, :boolean, null: false, default: true
    end
  end
end
