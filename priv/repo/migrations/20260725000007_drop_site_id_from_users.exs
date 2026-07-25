defmodule ThamaniDawa.Repo.Migrations.DropSiteIdFromUsers do
  use Ecto.Migration

  def change do
    drop index(:users, [:site_id])

    alter table(:users) do
      remove :site_id, references(:sites, on_delete: :nilify_all)
    end
  end
end
