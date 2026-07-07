defmodule ThamaniDawa.Repo.Migrations.AddOrganizationsNameUniqueIndex do
  use Ecto.Migration

  def change do
    create unique_index(:organizations, [:name])
  end
end
