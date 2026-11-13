defmodule ThamaniDawa.Repo.Migrations.CreateGoodsReceipts do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :next_goods_receipt_number, :integer, null: false, default: 0
    end

    create table(:goods_receipts) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :number, :string, null: false
      add :posting_key, :uuid, null: false
      add :received_at, :utc_datetime, null: false
      add :received_by_id, references(:users, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:goods_receipts, [:organization_id, :number])
    create unique_index(:goods_receipts, [:organization_id, :posting_key])
    create index(:goods_receipts, [:organization_id, :received_at])

    alter table(:batches) do
      add :goods_receipt_id, references(:goods_receipts, on_delete: :nilify_all)
    end

    create index(:batches, [:goods_receipt_id])
  end
end
