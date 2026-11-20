defmodule ThamaniDawa.Batches.LogisticUnit do
  @moduledoc """
  A physical logistic unit identified by an SSCC — the case (or pallet) a
  shipper SSCC labels. A unit owns one or more `batch` lines (its contents):
  a single-lot case holds one line, a mixed case holds several. Loose stock
  has no unit. Breaking a unit disaggregates its contents into child units
  (`parent_logistic_unit_id`) and retires the parent to `:disaggregated`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds [:case, :pallet]
  @statuses [:active, :disaggregated]
  @sources [:inbound, :minted]

  schema "logistic_units" do
    field :sscc, :string
    field :kind, Ecto.Enum, values: @kinds, default: :case
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :source, Ecto.Enum, values: @sources, default: :inbound

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :site, ThamaniDawa.Sites.Site
    belongs_to :goods_receipt, ThamaniDawa.GoodsReceipts.GoodsReceipt
    belongs_to :parent_logistic_unit, __MODULE__

    has_many :batches, ThamaniDawa.Batches.Batch

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds
  def statuses, do: @statuses
  def sources, do: @sources

  def changeset(unit, attrs) do
    unit
    |> cast(attrs, [
      :organization_id,
      :sscc,
      :kind,
      :status,
      :source,
      :site_id,
      :goods_receipt_id,
      :parent_logistic_unit_id
    ])
    |> validate_required([:organization_id, :sscc])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:site_id)
    |> foreign_key_constraint(:goods_receipt_id)
    |> foreign_key_constraint(:parent_logistic_unit_id)
    |> unique_constraint([:organization_id, :sscc],
      name: :logistic_units_organization_id_sscc_index,
      message: "already exists for this organization"
    )
  end
end
