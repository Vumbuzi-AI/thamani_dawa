defmodule ThamaniDawa.Repo.Migrations.AddOrganizationsNameKey do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :name_key, :string
    end

    execute "UPDATE organizations SET name_key = replace(slug, '-', '')", ""

    create unique_index(:organizations, [:name_key])
  end
end
