defmodule ThamaniDawa.Requisitions.Requisition do
  use Ecto.Schema
  import Ecto.Changeset

  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.Sites.Site

  schema "requisitions" do
    field :quantity, :integer
    field :urgency, Ecto.Enum, values: [:routine, :urgent], default: :routine

    field :status, Ecto.Enum,
      values: [:pending, :approved, :rejected, :partially_fulfilled, :fulfilled, :cancelled],
      default: :pending

    field :notes, :string
    field :rejection_reason, :string
    field :needs_reorder, :boolean, default: false
    field :reviewed_at, :utc_datetime

    belongs_to :organization, Organization
    belongs_to :site, Site
    belongs_to :product, Product
    belongs_to :requested_by, User, foreign_key: :requested_by_id
    belongs_to :reviewed_by, User, foreign_key: :reviewed_by_id

    has_many :fulfillment_batches, Batch, foreign_key: :requisition_id

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for a site requesting stock from the organization."
  def create_changeset(requisition, attrs) do
    requisition
    |> cast(attrs, [:site_id, :product_id, :quantity, :urgency, :notes])
    |> validate_required([:site_id, :product_id, :quantity])
    |> validate_number(:quantity, greater_than: 0)
    |> foreign_key_constraint(:site_id)
    |> foreign_key_constraint(:product_id)
  end

  @doc """
  Changeset applied when an admin approves or rejects a pending requisition.
  `rejection_reason` is required only when rejecting.
  """
  def review_changeset(requisition, attrs) do
    requisition
    |> cast(attrs, [:status, :reviewed_by_id, :reviewed_at, :rejection_reason, :needs_reorder])
    |> validate_required([:status, :reviewed_by_id, :reviewed_at])
    |> validate_inclusion(:status, [:approved, :rejected])
    |> validate_rejection_reason()
    |> foreign_key_constraint(:reviewed_by_id)
  end

  defp validate_rejection_reason(changeset) do
    case get_field(changeset, :status) do
      :rejected -> validate_required(changeset, [:rejection_reason])
      _ -> changeset
    end
  end
end
