defmodule ThamaniDawa.GoodsReceipts.ReceivingDiscrepancy do
  @moduledoc """
  A unit (or, for a large unverified-identity group, a quantity) that an
  SSCC's registered contents claimed should be in a delivery but wasn't
  physically confirmed at receiving. Deliberately not a `Batch` — there is
  no physical stock behind it — and never auto-reported to EPCIS: the
  receiving org was never confirmed to be in possession of it, so only a
  later investigation (closing it as `found`, `lost`, or `stolen`) has
  grounds to report anything.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @reasons [:missing]
  @statuses [:open, :found, :lost, :stolen]
  @outcomes [:supplier_sending_balance, :credit_note, :write_off]

  schema "receiving_discrepancies" do
    field :sscc, :string
    field :gtin, :string
    field :batch_no, :string
    field :serial, :string
    field :quantity, :integer
    field :expiry_date, :date
    field :reason, Ecto.Enum, values: @reasons, default: :missing
    field :status, Ecto.Enum, values: @statuses, default: :open
    field :resolution_reference, :string
    field :outcome, Ecto.Enum, values: @outcomes
    field :resolution_note, :string
    field :resolved_at, :utc_datetime

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :goods_receipt, ThamaniDawa.GoodsReceipts.GoodsReceipt
    belongs_to :resolved_by, ThamaniDawa.Accounts.User
    belongs_to :product, ThamaniDawa.Products.Product
    belongs_to :site, ThamaniDawa.Sites.Site

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def outcomes, do: @outcomes

  @doc false
  def changeset(discrepancy, attrs) do
    discrepancy
    |> cast(attrs, [
      :sscc,
      :gtin,
      :batch_no,
      :serial,
      :quantity,
      :reason,
      :organization_id,
      :goods_receipt_id,
      :product_id,
      :site_id,
      :expiry_date
    ])
    |> validate_required([:quantity, :organization_id, :goods_receipt_id],
      message: "can't be blank"
    )
    |> validate_number(:quantity, greater_than: 0)
    |> foreign_key_constraint(:goods_receipt_id)
  end

  @doc "Changeset applied when an investigation resolves a discrepancy."
  def resolve_changeset(discrepancy, attrs) do
    discrepancy
    |> cast(attrs, [:status, :resolution_reference, :resolved_by_id, :outcome, :resolution_note])
    |> validate_required([:status], message: "can't be blank")
    |> validate_inclusion(:status, [:found, :lost, :stolen])
    |> then(fn changeset ->
      if get_field(changeset, :status) in [:lost, :stolen] do
        validate_required(changeset, [:resolution_reference],
          message: "is required to close this out as lost or stolen"
        )
      else
        changeset
      end
    end)
    |> put_change(:resolved_at, DateTime.utc_now(:second))
  end
end
