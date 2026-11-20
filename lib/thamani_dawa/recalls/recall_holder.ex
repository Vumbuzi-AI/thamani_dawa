defmodule ThamaniDawa.Recalls.RecallHolder do
  use Ecto.Schema
  import Ecto.Changeset

  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Recalls.Recall

  schema "recall_holders" do
    field :quantity_at_recall, :integer
    field :acknowledged_at, :utc_datetime

    belongs_to :recall, Recall
    belongs_to :organization, Organization
    belongs_to :batch, Batch
    belongs_to :acknowledged_by, User, foreign_key: :acknowledged_by_id

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for snapshotting a batch caught by a recall cascade."
  def create_changeset(holder, attrs) do
    holder
    |> cast(attrs, [:recall_id, :organization_id, :batch_id, :quantity_at_recall])
    |> validate_required([:recall_id, :organization_id, :batch_id, :quantity_at_recall])
    |> foreign_key_constraint(:recall_id)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:batch_id)
    |> unique_constraint([:recall_id, :batch_id])
  end

  @doc "Changeset applied when the holder's organization acknowledges the recall."
  def acknowledge_changeset(holder, attrs) do
    holder
    |> cast(attrs, [:acknowledged_at, :acknowledged_by_id])
    |> validate_required([:acknowledged_at, :acknowledged_by_id])
    |> foreign_key_constraint(:acknowledged_by_id)
  end
end
