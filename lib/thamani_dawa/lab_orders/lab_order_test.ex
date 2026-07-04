defmodule ThamaniDawa.LabOrders.LabOrderTest do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:pending, :completed, :verified]

  schema "lab_order_tests" do
    field :organization_id, :id
    field :lab_order_id, :id
    field :lab_test_id, :id
    field :template_id, :id
    field :results, :map, default: %{}
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :sample_collected_on, :date
    field :test_performed_on, :date
    field :performed_by_id, :id
    field :verified_by_id, :id
    field :verified_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(lab_order_test, attrs) do
    lab_order_test
    |> cast(attrs, [
      :lab_test_id,
      :template_id,
      :results,
      :status,
      :sample_collected_on,
      :test_performed_on,
      :performed_by_id,
      :verified_by_id,
      :verified_at
    ])
    |> validate_required([:lab_test_id])
    |> foreign_key_constraint(:lab_test_id)
    |> foreign_key_constraint(:lab_order_id)
    |> foreign_key_constraint(:template_id)
    |> foreign_key_constraint(:performed_by_id)
    |> foreign_key_constraint(:verified_by_id)
  end

  @doc "The valid lab order test statuses (§4.4 of project.md)."
  def statuses, do: @statuses
end
