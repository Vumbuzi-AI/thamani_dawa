defmodule ThamaniDawa.GoodsReceipts.GoodsReceipt do
  use Ecto.Schema
  import Ecto.Changeset

  schema "goods_receipts" do
    field :number, :string
    field :posting_key, Ecto.UUID
    field :received_at, :utc_datetime

    # Set only for distributor-portal receipts, where the sender's GLN is
    # resolved live (one party per whole receipt) instead of picking a
    # stored `Suppliers.Supplier` per line — see `ThamaniDawa.GoodsReceipts.receive_delivery/5`.
    field :origin_gln, :string
    field :origin_company, :string
    field :origin_address, :string
    field :origin_po_box, :string
    field :is_return, :boolean, default: false

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :received_by, ThamaniDawa.Accounts.User
    belongs_to :origin_site, ThamaniDawa.Sites.Site
    belongs_to :reference_receipt, __MODULE__
    has_many :items, ThamaniDawa.Batches.Batch, foreign_key: :goods_receipt_id
    has_many :attachments, ThamaniDawa.GoodsReceipts.Attachment

    timestamps(type: :utc_datetime)
  end

  def changeset(receipt, attrs) do
    receipt
    |> cast(attrs, [
      :number,
      :posting_key,
      :received_at,
      :received_by_id,
      :is_return,
      :reference_receipt_id
    ])
    |> validate_required([:number, :posting_key, :received_at, :received_by_id])
    |> unique_constraint(:number, name: :goods_receipts_organization_id_number_index)
    |> unique_constraint(:posting_key, name: :goods_receipts_organization_id_posting_key_index)
    |> foreign_key_constraint(:received_by_id)
  end
end
