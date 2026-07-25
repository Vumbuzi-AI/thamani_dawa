defmodule ThamaniDawa.Repo.Migrations.AddCurrentSiteIdToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :current_site_id, references(:sites, on_delete: :nilify_all)
    end

    create index(:users, [:current_site_id])
  end
end
