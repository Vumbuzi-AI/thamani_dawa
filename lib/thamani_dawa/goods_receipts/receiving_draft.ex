defmodule ThamaniDawa.GoodsReceipts.ReceivingDraft do
  use Ecto.Schema
  import Ecto.Changeset

  schema "receiving_drafts" do
    field :origin, :map
    field :posting_key, Ecto.UUID

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :user, ThamaniDawa.Accounts.User
    has_many :attachments, ThamaniDawa.GoodsReceipts.ReceivingDraftAttachment

    timestamps(type: :utc_datetime)
  end

  def changeset(draft, attrs) do
    draft
    |> cast(attrs, [:origin, :posting_key, :organization_id, :user_id])
    |> validate_required([:posting_key, :organization_id, :user_id])
    |> unique_constraint([:organization_id, :user_id])
  end
end
