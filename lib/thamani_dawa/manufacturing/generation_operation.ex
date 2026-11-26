defmodule ThamaniDawa.Manufacturing.GenerationOperation do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending allocating reconciliation_required completed failed)
  @allocation_statuses ~w(pending allocating reconciliation_required completed failed not_required)

  schema "manufacturer_generation_operations" do
    field :operation_key, Ecto.UUID
    field :serial_quantity, :integer
    field :sscc_quantity, :integer, default: 0
    field :status, :string, default: "pending"
    field :serial_allocation_status, :string, default: "pending"
    field :sscc_allocation_status, :string, default: "pending"
    field :serial_request_payload, :map
    field :serial_response, :map
    field :sscc_request_payload, :map
    field :sscc_attempted_at, :utc_datetime
    field :reconciliation_note, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :product, ThamaniDawa.Manufacturing.Product, foreign_key: :manufacturer_product_id
    belongs_to :batch, ThamaniDawa.Manufacturing.Batch, foreign_key: :manufacturer_batch_id

    timestamps(type: :utc_datetime)
  end

  def changeset(operation, attrs) do
    operation
    |> cast(attrs, [
      :operation_key,
      :serial_quantity,
      :sscc_quantity,
      :status,
      :serial_allocation_status,
      :sscc_allocation_status,
      :serial_request_payload,
      :serial_response,
      :sscc_request_payload,
      :sscc_attempted_at,
      :reconciliation_note,
      :started_at,
      :completed_at
    ])
    |> validate_required([:operation_key, :serial_quantity, :status, :serial_allocation_status])
    |> validate_number(:serial_quantity, greater_than: 0)
    |> validate_number(:sscc_quantity, greater_than_or_equal_to: 0)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:serial_allocation_status, @allocation_statuses)
    |> validate_inclusion(:sscc_allocation_status, @allocation_statuses)
    |> unique_constraint(:operation_key)
  end
end
