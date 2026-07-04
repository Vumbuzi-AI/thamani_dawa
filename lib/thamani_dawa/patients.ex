defmodule ThamaniDawa.Patients do
  @moduledoc """
  Patients (§4.2), scoped to the organization rather than a single site — a
  chain's patient can be recognized at any of its branches.
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Patients.Patient

  @doc "Lists an organization's patients."
  def list_patients(organization_id) do
    Repo.all(from p in Patient, where: p.organization_id == ^organization_id)
  end

  @doc "Gets a single patient scoped to an organization. Raises if not found."
  def get_patient!(organization_id, id) do
    Repo.get_by!(Patient, id: id, organization_id: organization_id)
  end

  @doc "Creates a patient under the given organization."
  def create_patient(organization_id, attrs) when is_integer(organization_id) do
    %Patient{}
    |> Patient.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.insert()
  end
end
