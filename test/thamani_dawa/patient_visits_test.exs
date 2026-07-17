defmodule ThamaniDawa.PatientVisitsTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.PatientVisits

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.PatientsFixtures
  import ThamaniDawa.SitesFixtures

  describe "create_patient_visit/2" do
    test "creates a patient visit for a patient in the same organization" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})
      user = staff_fixture(%{organization_id: organization.id})

      assert {:ok, visit} =
               PatientVisits.create_patient_visit(organization.id, %{
                 site_id: site.id,
                 patient_id: patient.id,
                 user_id: user.id,
                 visit_type: :pharmacy
               })

      assert visit.patient_id == patient.id
    end

    test "rejects a patient_id belonging to a different organization" do
      organization = organization_fixture()
      other_organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      hostile_patient = patient_fixture(%{organization_id: other_organization.id})
      user = staff_fixture(%{organization_id: organization.id})

      assert {:error, changeset} =
               PatientVisits.create_patient_visit(organization.id, %{
                 site_id: site.id,
                 patient_id: hostile_patient.id,
                 user_id: user.id,
                 visit_type: :pharmacy
               })

      assert %{patient_id: ["must belong to the same organization"]} = errors_on(changeset)
    end
  end
end
