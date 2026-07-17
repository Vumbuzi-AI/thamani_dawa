defmodule ThamaniDawa.PatientsTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Patients
  alias ThamaniDawa.Patients.Patient

  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.PatientsFixtures

  describe "create_patient/2" do
    test "requires a full name" do
      organization = organization_fixture()
      assert {:error, changeset} = Patients.create_patient(organization.id, %{age: 30})
      assert %{full_name: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires a date of birth or an age" do
      organization = organization_fixture()

      assert {:error, changeset} =
               Patients.create_patient(organization.id, %{full_name: "Jane Doe"})

      assert %{date_of_birth: ["date of birth or age is required"]} = errors_on(changeset)
    end

    test "validates national_id is exactly 8 characters if provided" do
      organization = organization_fixture()

      assert {:error, changeset} =
               Patients.create_patient(organization.id, %{
                 full_name: "Jane Doe",
                 age: 30,
                 gsrn: 9,
                 national_id: "1234567"
               })

      assert %{national_id: ["must be exactly 8 characters"]} = errors_on(changeset)

      assert {:error, changeset} =
               Patients.create_patient(organization.id, %{
                 full_name: "Jane Doe",
                 age: 30,
                 gsrn: 10,
                 national_id: "123456789"
               })

      assert %{national_id: ["must be exactly 8 characters"]} = errors_on(changeset)
    end

    test "rejects a national_id containing letters" do
      organization = organization_fixture()

      assert {:error, changeset} =
               Patients.create_patient(organization.id, %{
                 full_name: "Jane Doe",
                 age: 30,
                 gsrn: 11,
                 national_id: "1234567A"
               })

      assert %{national_id: ["must contain only numbers"]} = errors_on(changeset)
    end

    test "validates phone number is a valid Kenyan format if provided" do
      organization = organization_fixture()

      assert {:error, changeset} =
               Patients.create_patient(organization.id, %{
                 full_name: "Jane Doe",
                 age: 30,
                 gsrn: 11,
                 phone: "0812345678"
               })

      assert %{phone: ["must be a valid Kenyan phone number (e.g. 0712345678 or +254712345678)"]} =
               errors_on(changeset)

      assert {:error, changeset} =
               Patients.create_patient(organization.id, %{
                 full_name: "Jane Doe",
                 age: 30,
                 gsrn: 12,
                 phone: "+254812345678"
               })

      assert %{phone: ["must be a valid Kenyan phone number (e.g. 0712345678 or +254712345678)"]} =
               errors_on(changeset)
    end

    test "creates a patient scoped to the organization given only an age" do
      organization = organization_fixture()

      assert {:ok, %Patient{} = patient} =
               Patients.create_patient(organization.id, %{
                 full_name: "Jane Doe",
                 age: 34,
                 gender: "female",
                 phone: "0700000000",
                 gsrn: 1
               })

      assert patient.organization_id == organization.id
      assert patient.full_name == "Jane Doe"
      assert patient.age == 34
    end

    test "creates a patient scoped to the organization given only a date of birth" do
      organization = organization_fixture()

      assert {:ok, %Patient{} = patient} =
               Patients.create_patient(organization.id, %{
                 full_name: "John Doe",
                 date_of_birth: ~D[1990-01-01],
                 gsrn: 2
               })

      assert patient.date_of_birth == ~D[1990-01-01]
    end

    test "allows the same patient name across organizations" do
      organization_a = organization_fixture()
      organization_b = organization_fixture()

      assert {:ok, _} =
               Patients.create_patient(organization_a.id, %{
                 full_name: "Jane Doe",
                 age: 30,
                 gsrn: 3
               })

      assert {:ok, _} =
               Patients.create_patient(organization_b.id, %{
                 full_name: "Jane Doe",
                 age: 30,
                 gsrn: 4
               })
    end
  end

  describe "list_patients/1" do
    test "only returns patients for the given organization" do
      organization_a = organization_fixture()
      organization_b = organization_fixture()

      patient_a = patient_fixture(%{organization_id: organization_a.id})
      patient_fixture(%{organization_id: organization_b.id})

      assert [%Patient{id: id}] = Patients.list_patients(organization_a.id)
      assert id == patient_a.id
    end
  end

  describe "get_patient!/2" do
    test "raises when the patient belongs to a different organization" do
      other_organization = organization_fixture()
      patient = patient_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        Patients.get_patient!(other_organization.id, patient.id)
      end
    end
  end
end
