defmodule ThamaniDawa.Prescriptions.Prescription do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:pending, :partially_dispensed, :completed, :cancelled]

  schema "prescriptions" do
    field :organization_id, :id
    field :user_id, :id
    field :patient_visit_id, :id
    field :payment_type, :string
    field :has_paid, :boolean, default: false
    field :total_amount, :decimal
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :notes, :string
    field :doctors_note, :string
    field :is_external, :boolean, default: false
    field :source_facility, :string
    field :referring_doctor, :string
    field :referral_date, :time

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(prescription, attrs) do
    prescription
    |> cast(attrs, [
      :user_id,
      :patient_visit_id,
      :payment_type,
      :has_paid,
      :total_amount,
      :status,
      :notes,
      :doctors_note,
      :is_external,
      :source_facility,
      :referring_doctor,
      :referral_date
    ])
    |> validate_required([:patient_visit_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:patient_visit_id)
  end

  @doc "The valid prescription statuses (§4.3 of project.md)."
  def statuses, do: @statuses
end
