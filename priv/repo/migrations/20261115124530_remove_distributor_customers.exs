defmodule ThamaniDawa.Repo.Migrations.RemoveDistributorCustomers do
  use Ecto.Migration

  def change do
    alter table(:distributor_shipments) do
      remove :destination_customer_id, references(:distributor_customers, on_delete: :nilify_all)
      add :destination_site_id, references(:sites, on_delete: :nilify_all)
    end

    create index(:distributor_shipments, [:destination_site_id])

    drop table(:distributor_customers)
  end
end
