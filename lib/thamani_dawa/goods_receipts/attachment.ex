defmodule ThamaniDawa.GoodsReceipts.Attachment do
  use Ecto.Schema
  import Ecto.Changeset

  @doc_types [:grn, :invoice, :other]

  schema "goods_receipt_attachments" do
    field :doc_type, Ecto.Enum, values: @doc_types
    field :filename, :string
    field :path, :string
    field :content_type, :string
    field :byte_size, :integer

    belongs_to :goods_receipt, ThamaniDawa.GoodsReceipts.GoodsReceipt
    belongs_to :uploaded_by, ThamaniDawa.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def doc_types, do: @doc_types

  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [
      :doc_type,
      :filename,
      :path,
      :content_type,
      :byte_size,
      :goods_receipt_id,
      :uploaded_by_id
    ])
    |> validate_required([:doc_type, :filename, :path, :goods_receipt_id])
    |> foreign_key_constraint(:goods_receipt_id)
  end
end
