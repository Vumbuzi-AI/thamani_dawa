defmodule ThamaniDawa.Repo.Migrations.AddUniqueIndexOnBatchesOrgProductSiteBatchNo do
  use Ecto.Migration

  def change do
    create unique_index(:batches, [:organization_id, :product_id, :site_id, :batch_no],
             name: :batches_org_product_site_batch_no_index
           )
  end
end
