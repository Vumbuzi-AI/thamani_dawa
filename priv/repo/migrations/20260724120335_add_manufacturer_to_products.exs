defmodule ThamaniDawa.Repo.Migrations.AddManufacturerToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :manufacturer, :string
    end
  end
end
