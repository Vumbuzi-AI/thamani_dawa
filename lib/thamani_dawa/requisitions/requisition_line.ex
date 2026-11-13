defmodule ThamaniDawa.Requisitions.RequisitionLine do
  use Ecto.Schema
  import Ecto.Changeset

  schema "requisition_lines" do
    field :requested_quantity, :integer
    field :approved_quantity, :integer

    field :status, Ecto.Enum,
      values: [
        :pending,
        :approved,
        :partially_approved,
        :rejected,
        :partially_fulfilled,
        :fulfilled
      ],
      default: :pending

    field :rejection_reason, :string
    field :reviewed_at, :utc_datetime

    belongs_to :requisition, ThamaniDawa.Requisitions.Requisition
    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :product, ThamaniDawa.Products.Product
    belongs_to :reviewed_by, ThamaniDawa.Accounts.User
    has_many :fulfillments, ThamaniDawa.Requisitions.RequisitionFulfillment

    timestamps(type: :utc_datetime)
  end

  def changeset(line, attrs) do
    line
    |> cast(attrs, [:product_id, :requested_quantity])
    |> validate_required([:product_id, :requested_quantity])
    |> validate_number(:requested_quantity, greater_than: 0)
    |> foreign_key_constraint(:product_id)
  end
end
