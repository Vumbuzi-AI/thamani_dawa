defmodule ThamaniDawa.PatientVisits do
  @moduledoc """
  Patient visits link a patient to a site (and the staff member who served
  them) for a single encounter — lab orders and prescriptions can optionally
  be tied back to the visit they arose from.
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Patients.Patient
  alias ThamaniDawa.PatientVisits.PatientVisit
  alias ThamaniDawa.Repo

  @doc "Lists an organization's patient visits."
  def list_patient_visits(organization_id) do
    Repo.all(from pv in PatientVisit, where: pv.organization_id == ^organization_id)
  end

  @doc "Gets a single patient visit scoped to an organization. Raises if not found."
  def get_patient_visit!(organization_id, id) do
    Repo.get_by!(PatientVisit, id: id, organization_id: organization_id)
  end

  @doc "Creates a patient visit under the given organization."
  def create_patient_visit(organization_id, attrs) when is_integer(organization_id) do
    %PatientVisit{}
    |> PatientVisit.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> validate_patient_in_organization(organization_id)
    |> Repo.insert()
  end

  defp validate_patient_in_organization(changeset, organization_id) do
    case Ecto.Changeset.get_change(changeset, :patient_id) do
      nil ->
        changeset

      patient_id ->
        query =
          from p in Patient, where: p.id == ^patient_id and p.organization_id == ^organization_id

        if Repo.exists?(query) do
          changeset
        else
          Ecto.Changeset.add_error(changeset, :patient_id, "must belong to the same organization")
        end
    end
  end
end
