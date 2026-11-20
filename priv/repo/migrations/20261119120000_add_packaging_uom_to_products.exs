defmodule ThamaniDawa.Repo.Migrations.AddPackagingUomToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :pack_uom, :string
      add :units_per_pack, :integer
    end
  end
end
