defmodule ThamaniDawa.DangerousDrugRegistersTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.DangerousDrugRegisters
  alias ThamaniDawa.DangerousDrugRegisters.DangerousDrugRegister

  import ThamaniDawa.DangerousDrugRegistersFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures

  describe "create_dangerous_drug_register/2" do
    test "requires site_id, product_id, month and year" do
      organization = organization_fixture()

      assert {:error, changeset} = DangerousDrugRegisters.create_dangerous_drug_register(organization.id, %{})

      assert %{
               site_id: ["can't be blank"],
               product_id: ["can't be blank"],
               month: ["can't be blank"],
               year: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "defaults entries to an empty map and last_entry_number to 0" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id})

      assert {:ok, %DangerousDrugRegister{} = register} =
               DangerousDrugRegisters.create_dangerous_drug_register(organization.id, %{
                 site_id: site.id,
                 product_id: product.id,
                 month: 6,
                 year: 2026
               })

      assert register.organization_id == organization.id
      assert register.entries == %{}
      assert register.last_entry_number == 0
    end

    test "enforces uniqueness of (organization_id, product_id, month, year)" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      dangerous_drug_register_fixture(%{organization_id: organization.id, product_id: product.id, month: 3, year: 2026})

      assert {:error, changeset} =
               DangerousDrugRegisters.create_dangerous_drug_register(organization.id, %{
                 site_id: site_fixture(%{organization_id: organization.id}).id,
                 product_id: product.id,
                 month: 3,
                 year: 2026
               })

      assert %{product_id: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "list_dangerous_drug_registers/1" do
    test "only returns registers for the given organization" do
      organization_a = organization_fixture()
      organization_b = organization_fixture()

      register_a = dangerous_drug_register_fixture(%{organization_id: organization_a.id})
      dangerous_drug_register_fixture(%{organization_id: organization_b.id})

      assert [%DangerousDrugRegister{id: id}] = DangerousDrugRegisters.list_dangerous_drug_registers(organization_a.id)
      assert id == register_a.id
    end
  end

  describe "get_dangerous_drug_register!/2" do
    test "raises when the register belongs to a different organization" do
      other_organization = organization_fixture()
      register = dangerous_drug_register_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        DangerousDrugRegisters.get_dangerous_drug_register!(other_organization.id, register.id)
      end
    end
  end
end
