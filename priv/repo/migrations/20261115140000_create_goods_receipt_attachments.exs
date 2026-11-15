defmodule ThamaniDawa.Repo.Migrations.CreateGoodsReceiptAttachments do
  use Ecto.Migration

  def change do
    create table(:goods_receipt_attachments) do
      add :goods_receipt_id, references(:goods_receipts, on_delete: :delete_all), null: false
      add :doc_type, :string, null: false
      add :filename, :string, null: false
      add :path, :string, null: false
      add :content_type, :string
      add :byte_size, :integer
      add :uploaded_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:goods_receipt_attachments, [:goods_receipt_id])
  end
end
