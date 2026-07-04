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

      assert {:ok, %LabTest{} = lab_test} =
               LabTests.create_lab_test(organization.id, %{name: "Full Blood Count", price: Decimal.new("500.00")})

      assert lab_test.organization_id == organization.id
      assert lab_test.is_active == true
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
end
