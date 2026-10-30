defmodule ThamaniDawa.Repo.Migrations.AddOrgLevelStockToBatches do
  use Ecto.Migration

  def change do
    alter table(:batches) do
      modify :site_id, :integer, null: true
      add :source_batch_id, references(:batches, on_delete: :nilify_all)
    end

    create index(:batches, [:source_batch_id])

    create unique_index(
             :batches,
             [:organization_id, :product_id, :batch_no],
             name: :batches_org_product_batch_no_undispatched_index,
             where: "site_id IS NULL"
           )
  end
end
