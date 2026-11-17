defmodule ThamaniDawa.Repo.Migrations.AddOriginToGoodsReceipts do
  use Ecto.Migration

  def change do
    alter table(:goods_receipts) do
      add :origin_gln, :string
      add :origin_company, :string
      add :origin_address, :string
      add :origin_po_box, :string
      add :origin_site_id, references(:sites, on_delete: :nilify_all)
    end

    create index(:goods_receipts, [:origin_site_id])
  end
end
