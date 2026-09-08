defmodule ThamaniDawa.OrganizationsKindTest do
  use ThamaniDawa.DataCase, async: true

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures

  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Sites.Site

  describe "kind (serialisation.md §1)" do
    test "an organization created without a kind defaults to healthcare" do
      organization = organization_fixture()
      assert organization.kind == :healthcare
      assert Organizations.healthcare?(organization.id)
      refute Organizations.distributor?(organization.id)
    end

    test "signup carries the requested kind through, and a distributor gets a warehouse site" do
      org_attrs = %{
        name: "Acme Distributors",
        license_number: "GS1-1",
        kind: "distributor"
      }

      admin_attrs = valid_user_attributes()

      assert {:ok, %{organization: organization, site: site}} =
               Organizations.signup(org_attrs, admin_attrs)

      assert organization.kind == :distributor
      assert Organizations.distributor?(organization.id)
      assert site.site_type == :warehouse
    end

    test "a healthcare signup still gets a pharmacy default site" do
      org_attrs = %{name: "MedPoint", license_number: "LIC-1", kind: "healthcare"}
      admin_attrs = valid_user_attributes()

      assert {:ok, %{site: site}} = Organizations.signup(org_attrs, admin_attrs)
      assert site.site_type == :pharmacy
    end
  end
end
