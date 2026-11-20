defmodule ThamaniDawa.Repo.Migrations.AddSiteToDistributorMobileUsers do
  use Ecto.Migration

  def change do
    alter table(:distributor_mobile_users) do
      add :site_id, references(:sites, on_delete: :nilify_all)
    end

    create index(:distributor_mobile_users, [:site_id])
  end
end
