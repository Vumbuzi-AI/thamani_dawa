defmodule ThamaniDawa.LabOrders.LabOrderResult do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:pending, :collected, :completed]

  schema "lab_order_results" do
    field :organization_id, :id
    field :lab_order_id, :id
    field :lab_order_test_id, :integer
    field :lab_test_id, :id
    field :template_id, :integer
    field :results, :map, default: %{}
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :sample_collected_on, :date
    field :collection_notes, :string
    field :test_performed_on, :date
    field :performed_by_id, :id
    field :collected_by_id, :id
    field :sample_collection_description, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(lab_order_result, attrs) do
    lab_order_result
    |> cast(attrs, [
      :lab_order_test_id,
      :lab_test_id,
      :template_id,
      :results,
      :status,
      :sample_collected_on,
      :collection_notes,
      :test_performed_on,
      :performed_by_id,
      :collected_by_id,
      :sample_collection_description
    ])
    |> validate_required([:lab_test_id, :sample_collection_description])
    |> foreign_key_constraint(:lab_order_id)
    |> foreign_key_constraint(:performed_by_id)
    |> foreign_key_constraint(:collected_by_id)
  end

  @doc "The valid lab order result statuses (§4.4 of project.md)."
  def statuses, do: @statuses
end
