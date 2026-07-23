defmodule ThamaniDawa.PatientVisits.PatientVisit do
  use Ecto.Schema
  import Ecto.Changeset

  @visit_types [:pharmacy, :lab]

  schema "patient_visits" do
    field :visit_type, Ecto.Enum, values: @visit_types

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :patient, ThamaniDawa.Patients.Patient
    belongs_to :site, ThamaniDawa.Sites.Site
    belongs_to :user, ThamaniDawa.Accounts.User

    has_many :prescriptions, ThamaniDawa.Prescriptions.Prescription
    has_many :lab_orders, ThamaniDawa.LabOrders.LabOrder

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(patient_visit, attrs) do
    patient_visit
    |> cast(attrs, [:patient_id, :site_id, :user_id, :visit_type])
    |> validate_required([:patient_id, :site_id, :user_id, :visit_type])
    |> foreign_key_constraint(:patient_id)
    |> foreign_key_constraint(:site_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc "The valid patient visit types."
  def visit_types, do: @visit_types
end
