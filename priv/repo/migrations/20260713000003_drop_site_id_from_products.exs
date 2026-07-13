defmodule ThamaniDawa.Repo.Migrations.DropSiteIdFromProducts do
  use Ecto.Migration

  def change do
    drop index(:products, [:site_id])

    alter table(:products) do
      remove :site_id, references(:sites, on_delete: :delete_all), null: false
    end
  end
end
