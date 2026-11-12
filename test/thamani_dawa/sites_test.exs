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
      assert site.activities == [:pharmacy]
      assert site.is_active
    end

    test "trims whitespace from the signup-created site name" do
      organization = organization_fixture()

      assert {:ok, site} = Sites.create_default_site(organization.id, "  Mwangaza Pharmacy  ")
      assert site.name == "Mwangaza Pharmacy"
    end
  end

  describe "create_site/2" do
    test "requires a name, activities, and address" do
      organization = organization_fixture()
      assert {:error, changeset} = Sites.create_site(organization.id, %{})

      assert %{
               name: ["can't be blank"],
               activities: ["can't be blank"],
               address: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "trims whitespace from a site's name on create" do
      organization = organization_fixture()

      assert {:ok, site} =
               Sites.create_site(organization.id, %{
                 name: "  Main Branch  ",
                 activities: [:pharmacy],
                 address: "Kimathi Street"
               })

      assert site.name == "Main Branch"
    end
  end

  describe "get_site_by_gln/2" do
    test "resolves a scanned GLN (AI 414) to the site under that organization" do
      organization = organization_fixture()

      {:ok, site} =
        Sites.create_site(organization.id, %{
          name: "HQ",
          activities: [:distribution],
          gln: "6160001000001",
          address: "Industrial Area"
        })

      assert {:ok, found} = Sites.get_site_by_gln(organization.id, site.gln)
      assert found.id == site.id
    end

    test "does not resolve a GLN belonging to a different organization" do
      organization_a = organization_fixture()
      organization_b = organization_fixture()

      {:ok, site} =
        Sites.create_site(organization_a.id, %{
          name: "HQ",
          activities: [:distribution],
          gln: "6160001000002",
          address: "Industrial Area"
        })

      assert {:error, :not_found} = Sites.get_site_by_gln(organization_b.id, site.gln)
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

  describe "capabilities" do
    test "pharmacy?/1 identifies sites supporting pharmacy work" do
      assert Site.pharmacy?(%Site{activities: [:pharmacy]})
      assert Site.pharmacy?(%Site{activities: [:pharmacy, :laboratory]})
      refute Site.pharmacy?(%Site{activities: [:laboratory]})
      refute Site.pharmacy?(%Site{activities: [:distribution]})
      refute Site.pharmacy?(nil)
    end

    test "lab?/1 identifies sites supporting lab work" do
      assert Site.lab?(%Site{activities: [:laboratory]})
      assert Site.lab?(%Site{activities: [:pharmacy, :laboratory]})
      refute Site.lab?(%Site{activities: [:pharmacy]})
      refute Site.lab?(%Site{activities: [:distribution]})
      refute Site.lab?(nil)
    end

    test "validates combined pharmacy and laboratory activities" do
      organization = organization_fixture()

      # valid activities
      assert {:ok, _site} =
               Sites.create_site(organization.id, %{
                 name: "Joint Branch",
                 activities: [:pharmacy, :laboratory],
                 address: "Valid Address"
               })

      assert {:ok, _site} =
               Sites.create_site(organization.id, %{
                 name: "Pharmacy Branch",
                 activities: [:pharmacy],
                 address: "Valid Address"
               })

      assert {:ok, _site} =
               Sites.create_site(organization.id, %{
                 name: "Lab Branch",
                 activities: [:laboratory],
                 address: "Valid Address"
               })

      # invalid activity
      assert {:error, changeset} =
               Sites.create_site(organization.id, %{
                 name: "Unknown Branch",
                 activities: [:unknown_activity],
                 address: "Valid Address"
               })

      assert %{activities: ["is invalid"]} = errors_on(changeset)
    end

    test "rejects a malformed site GLN" do
      organization = organization_fixture()

      assert {:error, changeset} =
               Sites.create_site(organization.id, %{
                 name: "HQ",
                 activities: [:pharmacy],
                 gln: "not-a-gln",
                 address: "Valid Address"
               })

      assert %{gln: ["must be 13 digits"]} = errors_on(changeset)
    end
  end
end
