defmodule ThamaniDawa.Manufacturing.AggregationSession do
  use Ecto.Schema
  import Ecto.Changeset

  @types ~w(shipper pallet)
  @statuses ~w(draft scanning awaiting_sscc awaiting_label_verification reconciliation_required completed cancelled)
  @methods ~w(during_packing)

  schema "manufacturer_aggregation_sessions" do
    field :session_type, :string
    field :status, :string, default: "draft"
    field :preparation_method, :string
    field :expected_item_count, :integer
    field :finished_loading_at, :utc_datetime
    field :parent_verified_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :lock_version, :integer, default: 1

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :batch, ThamaniDawa.Manufacturing.Batch, foreign_key: :manufacturer_batch_id

    belongs_to :shipper_sscc, ThamaniDawa.Manufacturing.ShipperSscc,
      foreign_key: :manufacturer_shipper_sscc_id

    belongs_to :pallet, ThamaniDawa.Manufacturing.Pallet, foreign_key: :manufacturer_pallet_id
    belongs_to :created_by, ThamaniDawa.Accounts.User

    has_many :items, ThamaniDawa.Manufacturing.AggregationSessionItem,
      foreign_key: :manufacturer_aggregation_session_id,
      preload_order: [asc: :captured_at]

    timestamps(type: :utc_datetime)
  end

  def types, do: @types
  def statuses, do: @statuses

  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :session_type,
      :status,
      :preparation_method,
      :expected_item_count,
      :manufacturer_batch_id,
      :manufacturer_shipper_sscc_id,
      :manufacturer_pallet_id,
      :finished_loading_at,
      :parent_verified_at,
      :completed_at
    ])
    |> validate_required([:session_type, :status])
    |> validate_inclusion(:session_type, @types)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:preparation_method, @methods ++ [nil])
    |> validate_number(:expected_item_count, greater_than: 0)
    |> optimistic_lock(:lock_version)
  end
end
