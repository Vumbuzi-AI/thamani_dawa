defmodule ThamaniDawa.Repo.Migrations.AddProductAndSiteToReceivingDiscrepancies do
  use Ecto.Migration

  def change do
    alter table(:receiving_discrepancies) do
      add :product_id, references(:products, on_delete: :restrict)
      add :site_id, references(:sites, on_delete: :restrict)
      add :expiry_date, :date
    end
  end
end
