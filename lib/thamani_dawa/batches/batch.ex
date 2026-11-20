defmodule ThamaniDawa.Batches.Batch do
  use Ecto.Schema
  import Ecto.Changeset

  alias ThamaniDawa.GS1.Sscc

  @zones [:receiving, :storage, :quarantine, :dispatch]
  @statuses [
    :active,
    :quarantined,
    :damaged,
    :expired,
    :recalled,
    :stolen,
    :inactive,
    :non_sellable_other,
    :destroyed,
    :returned,
    :disaggregated
  ]

  schema "batches" do
    field :gtin, :string
    field :batch_no, :string
    field :serial, :string
    field :serials, {:array, :string}, default: []
    field :sscc, :string
    field :manufacturer, :string
    field :manufacture_date, :date
    field :expiry_date, :date
    field :quantity, :integer
    field :remaining_quantity, :integer
    field :cost_per_unit, :decimal
    field :received_at, :utc_datetime
    field :zone, Ecto.Enum, values: @zones, default: :receiving
    field :bin, :string
    field :status, Ecto.Enum, values: @statuses, default: :active

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :product, ThamaniDawa.Products.Product
    belongs_to :site, ThamaniDawa.Sites.Site
    belongs_to :supplier, ThamaniDawa.Suppliers.Supplier
    belongs_to :goods_receipt, ThamaniDawa.GoodsReceipts.GoodsReceipt
    belongs_to :approver, ThamaniDawa.Accounts.User, foreign_key: :approver_id
    belongs_to :source_batch, __MODULE__
    belongs_to :requisition, ThamaniDawa.Requisitions.Requisition
    belongs_to :logistic_unit, ThamaniDawa.Batches.LogisticUnit

    has_many :lab_consumable_usages, ThamaniDawa.LabOrders.LabConsumableUsage
    has_many :prescription_batch_dispenses, ThamaniDawa.Prescriptions.BatchDispense

    timestamps(type: :utc_datetime)
  end

  def zones, do: @zones
  def statuses, do: @statuses

  @doc """
  Changeset for dispatching a batch to a site. Approval fields are not set
  here — they are stamped later via `receive_changeset/2` when staff confirm
  physical receipt.
  """
  def changeset(batch, attrs) do
    batch
    |> cast(attrs, [
      :product_id,
      :site_id,
      :gtin,
      :batch_no,
      :serial,
      :serials,
      :sscc,
      :manufacturer,
      :manufacture_date,
      :expiry_date,
      :quantity,
      :remaining_quantity,
      :cost_per_unit,
      :supplier_id,
      :source_batch_id,
      :goods_receipt_id,
      :logistic_unit_id,
      :status
    ])
    |> validate_required([
      :product_id,
      :site_id,
      :gtin,
      :batch_no,
      :expiry_date,
      :quantity
    ])
    |> ThamaniDawa.Gtin.validate_gtin()
    |> validate_expiry_date()
    |> validate_number(:quantity, greater_than_or_equal_to: 0)
    |> validate_number(:remaining_quantity, greater_than_or_equal_to: 0)
    |> validate_inbound_sscc()
    |> foreign_key_constraint(:product_id)
    |> foreign_key_constraint(:site_id)
    |> foreign_key_constraint(:supplier_id)
    |> foreign_key_constraint(:goods_receipt_id)
    |> foreign_key_constraint(:source_batch_id)
    |> foreign_key_constraint(:logistic_unit_id)
    |> unique_constraint(:batch_no,
      name: :batches_org_product_site_batch_no_status_index,
      message: "has already been dispatched to this site in this status"
    )
  end

  @doc """
  Changeset for recording a batch received directly into a site's stock.
  `site_id` is now required — all batches must be site-bound from receipt.
  This replaces the old two-step org→site flow.
  """
  def org_intake_changeset(batch, attrs) do
    batch
    |> cast(attrs, [
      :product_id,
      :site_id,
      :gtin,
      :batch_no,
      :serial,
      :serials,
      :sscc,
      :manufacturer,
      :manufacture_date,
      :expiry_date,
      :quantity,
      :remaining_quantity,
      :cost_per_unit,
      :supplier_id,
      :goods_receipt_id,
      :logistic_unit_id,
      :status
    ])
    |> validate_required([
      :product_id,
      :site_id,
      :gtin,
      :batch_no,
      :expiry_date,
      :quantity
    ])
    |> ThamaniDawa.Gtin.validate_gtin()
    |> validate_expiry_date()
    |> validate_number(:quantity, greater_than_or_equal_to: 0)
    |> validate_number(:remaining_quantity, greater_than_or_equal_to: 0)
    |> validate_inbound_sscc()
    |> foreign_key_constraint(:product_id)
    |> foreign_key_constraint(:site_id)
    |> foreign_key_constraint(:supplier_id)
    |> foreign_key_constraint(:logistic_unit_id)
    |> unique_constraint(:batch_no,
      name: :batches_org_product_site_batch_no_status_index,
      message: "has already been dispatched to this site in this status"
    )
  end

  defp validate_expiry_date(changeset) do
    validate_change(changeset, :expiry_date, fn :expiry_date, date ->
      if Date.compare(date, ThamaniDawa.BusinessDate.today()) == :gt do
        []
      else
        [expiry_date: "must be in the future"]
      end
    end)
  end

  # Optional inbound SSCC captured at the dock (docs/PPB_TNT_INTEGRATION.md
  # §4.4). Only feeds PPB receiving events, so it never blocks posting — an
  # empty value means no case label was scanned, which falls back to the
  # class-level receiving event. A mistyped SSCC is rejected here rather than
  # stored and surfaced later as a Hub-side `INVALID_GS1_IDENTIFIER` reject.
  defp validate_inbound_sscc(changeset) do
    case get_change(changeset, :sscc) do
      nil ->
        changeset

      raw ->
        digits = String.trim(raw)

        cond do
          digits == "" ->
            put_change(changeset, :sscc, nil)

          not Regex.match?(~r/^\d+$/, digits) or String.length(digits) != 18 ->
            add_error(changeset, :sscc, "must be an 18-digit SSCC from the case label")

          Sscc.mod10_check_digit(String.slice(digits, 0..-2//1)) !=
              String.to_integer(String.slice(digits, -1..-1//1)) ->
            add_error(changeset, :sscc, "check digit does not match, rescan the case label")

          true ->
            put_change(changeset, :sscc, digits)
        end
    end
  end

  @doc """
  Changeset for confirming receipt of a dispatched batch. Casting `:quantity`
  is optional — pass it when the amount actually received differs from what
  was dispatched, which also resets `remaining_quantity` to match (a pending
  batch can't yet have anything dispensed from it).
  """
  def receive_changeset(batch, attrs) do
    batch
    |> cast(attrs, [:received_at, :approver_id, :quantity])
    |> validate_required([:received_at, :approver_id])
    |> validate_number(:quantity, greater_than_or_equal_to: 0)
    |> validate_received_quantity_not_greater_than_dispatched()
    |> put_remaining_quantity_from_received_quantity()
    |> foreign_key_constraint(:approver_id)
  end

  defp validate_received_quantity_not_greater_than_dispatched(changeset) do
    validate_change(changeset, :quantity, fn :quantity, quantity ->
      if quantity > changeset.data.quantity do
        [quantity: "cannot exceed the dispatched quantity"]
      else
        []
      end
    end)
  end

  defp put_remaining_quantity_from_received_quantity(changeset) do
    case get_change(changeset, :quantity) do
      nil -> changeset
      quantity -> put_change(changeset, :remaining_quantity, quantity)
    end
  end

  @doc """
  Changeset for an intra-warehouse location move (putaway, bin-to-bin
  relocation) — zone + bin only, never EPCIS-reportable
  (docs/PPB_TNT_INTEGRATION.md: "do not report intra-warehouse OBSERVE
  movements").
  """
  def location_changeset(batch, attrs) do
    batch
    |> cast(attrs, [:zone, :bin])
    |> validate_required([:zone])
  end

  @doc """
  Changeset for a batch status transition (damaged/expired/stolen/lost/
  exported/recalled/destroyed/returned — docs/PPB_TNT_INTEGRATION.md
  §4.3/§4.4). Enforces the spec's own transition rules rather than trusting
  the caller: `:damaged` may start from `:active` or `:quarantined`;
  `:expired`, `:stolen`, `:inactive`, `:non_sellable_other`, and `:returned`
  only from `:active`; `:recalled` overrides any state except `:destroyed`;
  `:destroyed` only from `:damaged`, `:expired`, or `:recalled`.
  """
  def status_changeset(batch, new_status) when new_status in @statuses do
    batch
    |> change(status: new_status)
    |> validate_status_transition()
  end

  defp validate_status_transition(changeset) do
    current = changeset.data.status

    if valid_status_transition?(current, get_change(changeset, :status)) do
      changeset
    else
      add_error(changeset, :status, "cannot move from #{current} to this status")
    end
  end

  defp valid_status_transition?(_current, nil), do: true
  defp valid_status_transition?(current, :damaged), do: current in [:active, :quarantined]

  defp valid_status_transition?(current, status)
       when status in [:expired, :stolen, :inactive, :non_sellable_other, :returned],
       do: current == :active

  defp valid_status_transition?(current, :recalled), do: current != :destroyed

  defp valid_status_transition?(current, :destroyed),
    do: current in [:damaged, :expired, :recalled]

  defp valid_status_transition?(_current, _status), do: false
end
