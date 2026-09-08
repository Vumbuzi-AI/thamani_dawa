defmodule ThamaniDawa.Repo.Migrations.AddKindToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :kind, :string, null: false, default: "healthcare"
    end
  end
end
