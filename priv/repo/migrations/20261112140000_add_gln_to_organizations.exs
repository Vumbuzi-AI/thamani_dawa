defmodule ThamaniDawa.Repo.Migrations.AddGlnToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :gln, :string
    end

    create unique_index(:organizations, [:gln])
  end
end
