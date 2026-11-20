defmodule ThamaniDawa.Recalls.Recall do
  use Ecto.Schema
  import Ecto.Changeset

  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.Recalls.RecallHolder

  schema "recalls" do
    field :gtin, :string
    field :batch_no, :string
    field :reference, :string
    field :classification, Ecto.Enum, values: [:class_i, :class_ii, :class_iii]
    field :reason, :string
    field :status, Ecto.Enum, values: [:open, :closed], default: :open
    field :closed_at, :utc_datetime

    belongs_to :initiated_by, User, foreign_key: :initiated_by_id
    belongs_to :closed_by, User, foreign_key: :closed_by_id
    has_many :holders, RecallHolder

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for issuing a new recall."
  def create_changeset(recall, attrs) do
    recall
    |> cast(attrs, [:gtin, :batch_no, :reference, :classification, :reason, :initiated_by_id])
    |> validate_required([:gtin, :batch_no, :reference, :classification, :initiated_by_id])
    |> foreign_key_constraint(:initiated_by_id)
  end

  @doc "Changeset applied when closing a recall."
  def close_changeset(recall, attrs) do
    recall
    |> cast(attrs, [:closed_at, :closed_by_id])
    |> validate_required([:closed_at, :closed_by_id])
    |> foreign_key_constraint(:closed_by_id)
    |> put_change(:status, :closed)
  end
end
