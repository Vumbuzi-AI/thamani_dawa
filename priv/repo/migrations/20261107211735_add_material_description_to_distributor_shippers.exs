defmodule ThamaniDawa.Repo.Migrations.AddMaterialDescriptionToDistributorShippers do
  use Ecto.Migration

  def change do
    alter table(:distributor_shippers) do
      add :material_description, :string
    end
  end
end
