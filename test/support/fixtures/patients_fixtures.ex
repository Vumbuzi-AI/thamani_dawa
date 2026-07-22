defmodule ThamaniDawa.PatientsFixtures do
  @moduledoc """
  Test helpers for creating entities via `ThamaniDawa.Patients`.
  """

  alias ThamaniDawa.OrganizationsFixtures
  alias ThamaniDawa.Patients

  def valid_patient_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      full_name: "Patient #{System.unique_integer()}",
      date_of_birth: ~D[1990-01-01],
      gender: "Female",
      phone: "0712345678",
      national_id: "12345678",
      gsrn: System.unique_integer([:positive])
    })
  end

  @doc "Creates a patient under a fresh organization unless `organization_id` is given."
  def patient_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn ->
        OrganizationsFixtures.organization_fixture().id
      end)

    {:ok, patient} =
      attrs
      |> valid_patient_attributes()
      |> then(&Patients.create_patient(organization_id, &1))

    patient
  end
end
