defmodule ThamaniDawa.Repo.Migrations.AddLatLongToSuppliers do
  use Ecto.Migration

  def change do
    alter table(:suppliers) do
      add :lat, :float
      add :long, :float
    end
  end
end
