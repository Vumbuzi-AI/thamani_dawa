defmodule ThamaniDawa.LabOrders.LabSpecimen do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:pending_collection, :collected, :received, :rejected]
  @specimen_types [:blood, :urine, :stool, :swab]

  schema "lab_specimens" do
    field :specimen_number, :string
    field :specimen_type, Ecto.Enum, values: @specimen_types
    field :status, Ecto.Enum, values: @statuses, default: :pending_collection
    field :collected_at, :utc_datetime
    field :received_at, :utc_datetime
    field :rejected_at, :utc_datetime
    field :rejection_reason, :string
    field :notes, :string

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :lab_order_result, ThamaniDawa.LabOrders.LabOrderResult
    belongs_to :collected_by, ThamaniDawa.Accounts.User, foreign_key: :collected_by_id
    belongs_to :received_by, ThamaniDawa.Accounts.User, foreign_key: :received_by_id
    belongs_to :rejected_by, ThamaniDawa.Accounts.User, foreign_key: :rejected_by_id

    has_many :lab_specimen_results, ThamaniDawa.LabOrders.LabSpecimenResult
    has_many :lab_order_results, through: [:lab_specimen_results, :lab_order_result]

    has_many :lab_consumable_usages, ThamaniDawa.LabOrders.LabConsumableUsage,
      foreign_key: :specimen_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(lab_specimen, attrs) do
    lab_specimen
    |> cast(attrs, [
      :specimen_number,
      :specimen_type,
      :status,
      :collected_by_id,
      :collected_at,
      :received_by_id,
      :received_at,
      :rejected_by_id,
      :rejected_at,
      :rejection_reason,
      :notes,
      :lab_order_result_id
    ])
    |> validate_required([:specimen_number, :specimen_type])
    |> validate_rejection_reason()
    |> unique_constraint([:organization_id, :specimen_number])
    |> foreign_key_constraint(:lab_order_result_id)
    |> foreign_key_constraint(:collected_by_id)
    |> foreign_key_constraint(:received_by_id)
    |> foreign_key_constraint(:rejected_by_id)
  end

  defp validate_rejection_reason(changeset) do
    if get_field(changeset, :status) == :rejected do
      validate_required(changeset, [:rejection_reason])
    else
      changeset
    end
  end

  @doc "The valid specimen statuses."
  def statuses, do: @statuses

  @doc "The valid specimen types (mirrors `LabOrderResult.sample_types/0`)."
  def specimen_types, do: @specimen_types
end
