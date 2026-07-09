defmodule ThamaniDawa.Repo.Migrations.ChangeSitesLatLongToFloat do
  use Ecto.Migration

  def up do
    alter table(:sites) do
      modify :lat, :float, from: :integer
      modify :long, :float, from: :integer
    end
  end

  def down do
    alter table(:sites) do
      modify :lat, :integer, from: :float
      modify :long, :integer, from: :float
    end
  end
end
