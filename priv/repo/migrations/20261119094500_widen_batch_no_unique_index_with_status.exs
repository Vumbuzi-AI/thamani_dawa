defmodule ThamaniDawa.Repo.Migrations.WidenBatchNoUniqueIndexWithStatus do
  use Ecto.Migration

  @moduledoc """
  Receiving a delivery can now split one manufacturer batch_no into
  multiple rows at the same site when part of it is confirmed in a
  different condition (e.g. 8 active + 2 damaged) — the old index would
  have rejected the second row outright. Widening it to include `status`
  keeps the original guarantee (the same batch_no can't be dispatched to a
  site twice in the *same* status) while allowing legitimate condition
  splits.
  """

  def change do
    drop unique_index(:batches, [:organization_id, :product_id, :site_id, :batch_no],
           name: :batches_org_product_site_batch_no_index
         )

    create unique_index(:batches, [:organization_id, :product_id, :site_id, :batch_no, :status],
             name: :batches_org_product_site_batch_no_status_index
           )
  end
end
