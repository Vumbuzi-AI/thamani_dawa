defmodule ThamaniDawa.LabTestsTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.LabTests
  alias ThamaniDawa.LabTests.LabTest

  import ThamaniDawa.LabTestsFixtures
  import ThamaniDawa.OrganizationsFixtures

  describe "create_lab_test/2" do
    test "requires name" do
      organization = organization_fixture()

      assert {:error, changeset} = LabTests.create_lab_test(organization.id, %{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "defaults is_active to true and scopes to the organization" do
      organization = organization_fixture()
      category = lab_test_category_fixture(%{organization_id: organization.id})

      assert {:ok, %LabTest{} = lab_test} =
               LabTests.create_lab_test(organization.id, %{
                 name: "Full Blood Count",
                 price: Decimal.new("500.00"),
                 category_id: category.id,
                 field_definitions: %{"haemoglobin" => %{"type" => "number"}}
               })

      assert lab_test.organization_id == organization.id
      assert lab_test.is_active == true
    end

    test "requires category_id" do
      organization = organization_fixture()

      assert {:error, changeset} =
               LabTests.create_lab_test(organization.id, valid_lab_test_attributes())

      assert %{category_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects a category_id that doesn't exist" do
      organization = organization_fixture()

      assert {:error, changeset} =
               LabTests.create_lab_test(
                 organization.id,
                 valid_lab_test_attributes(%{category_id: -1})
               )

      assert %{category_id: ["does not exist"]} = errors_on(changeset)
    end
  end

  describe "list_lab_tests/1" do
    test "only returns lab tests for the given organization" do
      organization_a = organization_fixture()
      organization_b = organization_fixture()

      lab_test_a = lab_test_fixture(%{organization_id: organization_a.id})
      lab_test_fixture(%{organization_id: organization_b.id})

      assert [%LabTest{id: id}] = LabTests.list_lab_tests(organization_a.id)
      assert id == lab_test_a.id
    end
  end

  describe "get_lab_test!/2" do
    test "raises when the lab test belongs to a different organization" do
      other_organization = organization_fixture()
      lab_test = lab_test_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        LabTests.get_lab_test!(other_organization.id, lab_test.id)
      end
    end
  end

  describe "update_lab_test/3" do
    test "updates the name of a lab test" do
      organization = organization_fixture()
      lab_test = lab_test_fixture(%{organization_id: organization.id})

      assert {:ok, %LabTest{name: "Updated Name"}} =
               LabTests.update_lab_test(organization.id, lab_test, %{name: "Updated Name"})
    end

    test "returns error changeset when name is blank" do
      organization = organization_fixture()
      lab_test = lab_test_fixture(%{organization_id: organization.id})

      assert {:error, changeset} =
               LabTests.update_lab_test(organization.id, lab_test, %{name: ""})

      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "raises when the lab test belongs to a different organization" do
      other_organization = organization_fixture()
      lab_test = lab_test_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        LabTests.update_lab_test(other_organization.id, lab_test, %{name: "Hack"})
      end
    end
  end

  describe "change_lab_test/2" do
    test "returns a changeset pre-populated with the lab test's current data" do
      organization = organization_fixture()
      lab_test = lab_test_fixture(%{organization_id: organization.id, name: "Malaria RDT"})

      changeset = LabTests.change_lab_test(lab_test, %{})

      assert changeset.data.name == "Malaria RDT"
      assert changeset.valid?
    end

    test "defaults attrs to an empty map when only the lab test is given" do
      lab_test = lab_test_fixture(%{name: "Malaria RDT"})

      changeset = LabTests.change_lab_test(lab_test)

      assert changeset.data.name == "Malaria RDT"
      assert changeset.changes == %{}
    end

    test "also accepts an existing changeset, merging new attrs onto its prior changes" do
      lab_test = lab_test_fixture()

      changeset =
        lab_test
        |> LabTests.change_lab_test(%{"price" => "999.00"})
        |> LabTests.change_lab_test(%{"name" => "Renamed"})

      assert Ecto.Changeset.get_change(changeset, :name) == "Renamed"
      assert Decimal.equal?(Ecto.Changeset.get_change(changeset, :price), Decimal.new("999.00"))
    end
  end

  describe "list_active_lab_tests/1" do
    test "returns active tests for the organization" do
      organization = organization_fixture()
      active = lab_test_fixture(%{organization_id: organization.id})

      assert [%LabTest{id: id}] = LabTests.list_active_lab_tests(organization.id)
      assert id == active.id
    end

    test "excludes inactive tests" do
      organization = organization_fixture()
      lab_test = lab_test_fixture(%{organization_id: organization.id})
      {:ok, _} = LabTests.update_lab_test(organization.id, lab_test, %{is_active: false})

      assert [] = LabTests.list_active_lab_tests(organization.id)
    end

    test "does not return active tests from another organization" do
      organization_a = organization_fixture()
      organization_b = organization_fixture()
      lab_test_fixture(%{organization_id: organization_b.id})

      assert [] = LabTests.list_active_lab_tests(organization_a.id)
    end

    test "orders results by category then name" do
      organization = organization_fixture()
      serology = lab_test_category_fixture(%{organization_id: organization.id, name: "Serology"})

      biochemistry =
        lab_test_category_fixture(%{organization_id: organization.id, name: "Biochemistry"})

      lab_test_fixture(%{
        organization_id: organization.id,
        category_id: serology.id,
        name: "Widal"
      })

      lab_test_fixture(%{
        organization_id: organization.id,
        category_id: biochemistry.id,
        name: "Urea"
      })

      lab_test_fixture(%{
        organization_id: organization.id,
        category_id: biochemistry.id,
        name: "Creatinine"
      })

      assert [
               %LabTest{name: "Creatinine"},
               %LabTest{name: "Urea"},
               %LabTest{name: "Widal"}
             ] = LabTests.list_active_lab_tests(organization.id)
    end
  end
end
