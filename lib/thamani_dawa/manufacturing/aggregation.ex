defmodule ThamaniDawa.Manufacturing.Aggregation do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(draft submitted approved rejected)

  schema "manufacturer_aggregations" do
    field :reference, :string
    field :status, :string, default: "draft"
    field :submitted_at, :utc_datetime
    field :approved_at, :utc_datetime
    field :rejected_at, :utc_datetime
    field :rejection_reason, :string
    field :item_count, :integer, virtual: true

    belongs_to :organization, ThamaniDawa.Organizations.Organization

    belongs_to :shipper_sscc, ThamaniDawa.Manufacturing.ShipperSscc,
      foreign_key: :manufacturer_shipper_sscc_id

    belongs_to :created_by, ThamaniDawa.Accounts.User
    belongs_to :approved_by, ThamaniDawa.Accounts.User
    belongs_to :rejected_by, ThamaniDawa.Accounts.User

    has_many :items, ThamaniDawa.Manufacturing.AggregationItem,
      foreign_key: :manufacturer_aggregation_id,
      preload_order: [asc: :scanned_at]

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(aggregation, attrs) do
    aggregation
    |> cast(attrs, [:reference, :status, :manufacturer_shipper_sscc_id, :rejection_reason])
    |> validate_inclusion(:status, @statuses)
  end
end
