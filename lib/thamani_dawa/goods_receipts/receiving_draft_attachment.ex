defmodule ThamaniDawa.GoodsReceipts.ReceivingDraftAttachment do
  use Ecto.Schema
  import Ecto.Changeset

  @doc_types [:delivery_note, :invoice, :po, :other]

  schema "receiving_draft_attachments" do
    field :doc_type, Ecto.Enum, values: @doc_types
    field :filename, :string
    field :path, :string
    field :content_type, :string
    field :byte_size, :integer

    belongs_to :receiving_draft, ThamaniDawa.GoodsReceipts.ReceivingDraft

    timestamps(type: :utc_datetime)
  end

  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:doc_type, :filename, :path, :content_type, :byte_size, :receiving_draft_id])
    |> validate_required([:doc_type, :filename, :path, :receiving_draft_id])
  end
end
