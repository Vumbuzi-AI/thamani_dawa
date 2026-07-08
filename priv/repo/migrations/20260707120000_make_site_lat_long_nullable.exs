defmodule ThamaniDawa.Repo.Migrations.MakeSiteLatLongNullable do
  use Ecto.Migration

  def change do
    alter table(:sites) do
      modify :lat, :float, null: true
      modify :long, :float, null: true
    end
  end
end
