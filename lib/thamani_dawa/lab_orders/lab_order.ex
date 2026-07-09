defmodule ThamaniDawa.LabOrders.LabOrder do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:pending, :in_progress, :completed, :verified, :cancelled]

  schema "lab_orders" do
    field :organization_id, :id
    field :site_id, :id
    field :patient_id, :id
    field :patient_visit_id, :id
    field :prescriber_name, :string
    field :ordered_by_id, :id
    field :urgency, :string
    field :payment_type, :string
    field :has_paid, :boolean, default: false
    field :total_amount, :decimal
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :lab_report, :string
    field :test_findings, :string
    field :lab_request, :string
    field :referring_facility, :string
    field :referring_doctor, :string
    field :referred_date, :time

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(lab_order, attrs) do
    lab_order
    |> cast(attrs, [
      :site_id,
      :patient_id,
      :patient_visit_id,
      :prescriber_name,
      :ordered_by_id,
      :urgency,
      :payment_type,
      :has_paid,
      :total_amount,
      :status,
      :lab_report,
      :test_findings,
      :lab_request,
      :referring_facility,
      :referring_doctor,
      :referred_date
    ])
    |> validate_required([:site_id, :patient_id, :patient_visit_id])
    |> foreign_key_constraint(:site_id)
    |> foreign_key_constraint(:patient_id)
    |> foreign_key_constraint(:patient_visit_id)
    |> foreign_key_constraint(:ordered_by_id)
  end

  @doc "The valid lab order statuses (§4.4 of project.md)."
  def statuses, do: @statuses
end
