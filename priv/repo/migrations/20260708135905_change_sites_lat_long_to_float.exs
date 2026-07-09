defmodule ThamaniDawa.Repo.Migrations.ChangeSitesLatLongToFloat do
  use Ecto.Migration

  def up do
    alter table(:sites) do
      modify :lat, :float, from: :integer, using: "lat::double precision"
      modify :long, :float, from: :integer, using: "long::double precision"
    end
  end

  def down do
    alter table(:sites) do
      modify :lat, :integer, from: :float, using: "round(lat)::integer"
      modify :long, :integer, from: :float, using: "round(long)::integer"
    end
  end
end
