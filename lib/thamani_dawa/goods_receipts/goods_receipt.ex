defmodule ThamaniDawa.GoodsReceipts.GoodsReceipt do
  use Ecto.Schema
  import Ecto.Changeset

  schema "goods_receipts" do
    field :number, :string
    field :posting_key, Ecto.UUID
    field :received_at, :utc_datetime

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :received_by, ThamaniDawa.Accounts.User
    has_many :items, ThamaniDawa.Batches.Batch, foreign_key: :goods_receipt_id

    timestamps(type: :utc_datetime)
  end

  def changeset(receipt, attrs) do
    receipt
    |> cast(attrs, [:number, :posting_key, :received_at, :received_by_id])
    |> validate_required([:number, :posting_key, :received_at, :received_by_id])
    |> unique_constraint(:number, name: :goods_receipts_organization_id_number_index)
    |> unique_constraint(:posting_key, name: :goods_receipts_organization_id_posting_key_index)
    |> foreign_key_constraint(:received_by_id)
  end
end
