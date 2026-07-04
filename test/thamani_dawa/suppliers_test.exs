defmodule ThamaniDawa.SuppliersTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Suppliers
  alias ThamaniDawa.Suppliers.Supplier

  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.SuppliersFixtures

  describe "create_supplier/2" do
    test "requires a name" do
      organization = organization_fixture()
      assert {:error, changeset} = Suppliers.create_supplier(organization.id, %{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "creates a supplier scoped to the organization" do
      organization = organization_fixture()

      assert {:ok, %Supplier{} = supplier} =
               Suppliers.create_supplier(organization.id, %{
                 name: "Acme Distributors",
                 phone: "0700000000",
                 email: "orders@acme.test"
               })

      assert supplier.organization_id == organization.id
      assert supplier.name == "Acme Distributors"
      assert supplier.is_active
    end

    test "allows the same supplier name across organizations" do
      organization_a = organization_fixture()
      organization_b = organization_fixture()

      assert {:ok, _} = Suppliers.create_supplier(organization_a.id, %{name: "Acme Distributors"})
      assert {:ok, _} = Suppliers.create_supplier(organization_b.id, %{name: "Acme Distributors"})
    end
  end

  describe "list_suppliers/1" do
    test "only returns suppliers for the given organization" do
      organization_a = organization_fixture()
      organization_b = organization_fixture()

      supplier_a = supplier_fixture(%{organization_id: organization_a.id})
      supplier_fixture(%{organization_id: organization_b.id})

      assert [%Supplier{id: id}] = Suppliers.list_suppliers(organization_a.id)
      assert id == supplier_a.id
    end
  end

  describe "get_supplier!/2" do
    test "raises when the supplier belongs to a different organization" do
      other_organization = organization_fixture()
      supplier = supplier_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        Suppliers.get_supplier!(other_organization.id, supplier.id)
      end
    end
  end
end
