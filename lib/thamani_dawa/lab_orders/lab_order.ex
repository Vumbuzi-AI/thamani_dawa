defmodule ThamaniDawa.LabOrders.LabOrder do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:pending, :in_progress, :completed, :verified, :cancelled]

  schema "lab_orders" do
    field :organization_id, :id
    field :site_id, :id
    field :patient_id, :id
    field :prescriber_name, :string
    field :ordered_by_id, :id
    field :urgency, :string
    field :payment_type, :string
    field :has_paid, :boolean, default: false
    field :total_amount, :decimal
    field :sample_collection_date, :date
    field :sample_collection_description, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :lab_report, :string
    field :test_findings, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(lab_order, attrs) do
    lab_order
    |> cast(attrs, [
      :site_id,
      :patient_id,
      :prescriber_name,
      :ordered_by_id,
      :urgency,
      :payment_type,
      :has_paid,
      :total_amount,
      :sample_collection_date,
      :sample_collection_description,
      :status,
      :lab_report,
      :test_findings
    ])
    |> validate_required([:site_id, :patient_id])
    |> foreign_key_constraint(:site_id)
    |> foreign_key_constraint(:patient_id)
    |> foreign_key_constraint(:ordered_by_id)
  end

  @doc "The valid lab order statuses (§4.4 of project.md)."
  def statuses, do: @statuses
end
