defmodule ThamaniDawa.SitesTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site

  import ThamaniDawa.OrganizationsFixtures

  describe "create_default_site/2" do
    test "creates a pharmacy-type site named after the organization" do
      organization = organization_fixture()

      assert {:ok, %Site{} = site} = Sites.create_default_site(organization.id, organization.name)
      assert site.organization_id == organization.id
      assert site.name == organization.name
      assert site.site_type == :pharmacy
      assert site.is_active
    end
  end

  describe "create_site/2" do
    test "requires a name, site_type, gln, and address" do
      organization = organization_fixture()
      assert {:error, changeset} = Sites.create_site(organization.id, %{})

      assert %{
               name: ["can't be blank"],
               site_type: ["can't be blank"],
               gln: ["can't be blank"],
               address: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "enforces globally unique gln across organizations" do
      organization_a = organization_fixture()
      organization_b = organization_fixture()

      assert {:ok, _site} =
               Sites.create_site(organization_a.id, %{
                 name: "HQ",
                 site_type: :warehouse,
                 gln: "0614141000005",
                 address: "Industrial Area"
               })

      assert {:error, changeset} =
               Sites.create_site(organization_b.id, %{
                 name: "Branch",
                 site_type: :pharmacy,
                 gln: "0614141000005",
                 address: "Kimathi Street"
               })

      assert %{gln: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "get_site_by_gln/2" do
    test "resolves a scanned GLN (AI 414) to the site under that organization" do
      organization = organization_fixture()

      {:ok, site} =
        Sites.create_site(organization.id, %{
          name: "HQ",
          site_type: :warehouse,
          gln: "0614141000005",
          address: "Industrial Area"
        })

      assert {:ok, found} = Sites.get_site_by_gln(organization.id, "0614141000005")
      assert found.id == site.id
    end

    test "does not resolve a GLN belonging to a different organization" do
      organization_a = organization_fixture()
      organization_b = organization_fixture()

      {:ok, _site} =
        Sites.create_site(organization_a.id, %{
          name: "HQ",
          site_type: :warehouse,
          gln: "0614141000005",
          address: "Industrial Area"
        })

      assert {:error, :not_found} = Sites.get_site_by_gln(organization_b.id, "0614141000005")
    end

    test "returns :not_found for an unknown GLN" do
      organization = organization_fixture()
      assert {:error, :not_found} = Sites.get_site_by_gln(organization.id, "0000000000000")
    end
  end

  describe "list_sites/1" do
    test "only returns sites for the given organization" do
      organization_a = organization_fixture()
      organization_b = organization_fixture()

      {:ok, site_a} = Sites.create_default_site(organization_a.id, organization_a.name)
      {:ok, _site_b} = Sites.create_default_site(organization_b.id, organization_b.name)

      assert [%Site{id: id}] = Sites.list_sites(organization_a.id)
      assert id == site_a.id
    end
  end
end
