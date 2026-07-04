defmodule ThamaniDawa.Prescriptions.Prescription do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:pending, :partially_dispensed, :completed, :cancelled]

  schema "prescriptions" do
    field :organization_id, :id
    field :site_id, :id
    field :patient_id, :id
    field :prescriber_name, :string
    field :prescriber_reg_no, :string
    field :entered_by_id, :id
    field :payment_type, :string
    field :has_paid, :boolean, default: false
    field :total_amount, :decimal
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(prescription, attrs) do
    prescription
    |> cast(attrs, [
      :site_id,
      :patient_id,
      :prescriber_name,
      :prescriber_reg_no,
      :entered_by_id,
      :payment_type,
      :has_paid,
      :total_amount,
      :status,
      :notes
    ])
    |> validate_required([:site_id, :patient_id])
    |> foreign_key_constraint(:site_id)
    |> foreign_key_constraint(:patient_id)
    |> foreign_key_constraint(:entered_by_id)
  end

  @doc "The valid prescription statuses (§4.3 of project.md)."
  def statuses, do: @statuses
end
