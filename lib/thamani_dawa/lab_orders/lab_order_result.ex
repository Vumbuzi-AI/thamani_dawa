defmodule ThamaniDawa.LabOrders.LabOrderResult do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:pending, :collected, :completed]
  @sample_types [:blood, :urine, :stool, :swab]

  schema "lab_order_results" do
    field :template_id, :integer
    field :results, :map, default: %{}
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :sample_collected_on, :date
    field :collection_notes, :string
    field :test_performed_on, :date
    field :sample_type, Ecto.Enum, values: @sample_types

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :lab_order, ThamaniDawa.LabOrders.LabOrder
    belongs_to :lab_test, ThamaniDawa.LabTests.LabTest
    belongs_to :performed_by, ThamaniDawa.Accounts.User, foreign_key: :performed_by_id
    belongs_to :collected_by, ThamaniDawa.Accounts.User, foreign_key: :collected_by_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(lab_order_result, attrs) do
    lab_order_result
    |> cast(attrs, [
      :lab_test_id,
      :template_id,
      :results,
      :status,
      :sample_collected_on,
      :collection_notes,
      :test_performed_on,
      :performed_by_id,
      :collected_by_id,
      :sample_type
    ])
    |> validate_required([:lab_test_id, :sample_type])
    |> foreign_key_constraint(:lab_order_id)
    |> foreign_key_constraint(:lab_test_id)
    |> foreign_key_constraint(:performed_by_id)
    |> foreign_key_constraint(:collected_by_id)
    |> unique_constraint([:lab_order_id, :lab_test_id],
      name: :lab_order_results_unique_test_per_order,
      message: "this test has already been added to this order"
    )
  end

  @doc "The valid lab order result statuses (§4.4 of project.md)."
  def statuses, do: @statuses

  @doc "The valid sample types (§4.4 of project.md)."
  def sample_types, do: @sample_types
end
