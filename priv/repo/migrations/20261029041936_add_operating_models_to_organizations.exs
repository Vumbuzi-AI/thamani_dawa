defmodule ThamaniDawa.Repo.Migrations.AddOperatingModelsToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :operating_models, {:array, :string}, null: false, default: ["pharmacy"]
    end
  end
end
