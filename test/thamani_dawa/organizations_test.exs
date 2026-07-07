defmodule ThamaniDawa.OrganizationsTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites.Site

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures

  describe "create_organization/1" do
    test "creates an organization with a name and license number" do
      assert {:ok, organization} =
               Organizations.create_organization(%{name: "Acme Pharmacy", license_number: "LIC-1"})

      assert organization.name == "Acme Pharmacy"
      assert organization.license_number == "LIC-1"
      assert organization.is_active
    end

    test "requires a name" do
      assert {:error, changeset} =
               Organizations.create_organization(%{license_number: "LIC-1"})

      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires a license number" do
      assert {:error, changeset} = Organizations.create_organization(%{name: "Acme Pharmacy"})
      assert %{license_number: ["can't be blank"]} = errors_on(changeset)
    end

    test "auto-generates a slug from the name when none is given" do
      assert {:ok, organization} =
               Organizations.create_organization(%{name: "Acme Pharmacy", license_number: "LIC-1"})

      assert organization.slug =~ ~r/^acme-pharmacy-[0-9a-f]{4}$/
    end

    test "strips accents when generating a slug" do
      assert {:ok, organization} =
               Organizations.create_organization(%{name: "Café Pharmacy", license_number: "LIC-1"})

      assert organization.slug =~ ~r/^cafe-pharmacy-[0-9a-f]{4}$/
    end

    test "requires a unique name" do
      organization_fixture(%{name: "City Pharmacy"})

      assert {:error, changeset} =
               Organizations.create_organization(%{name: "City Pharmacy", license_number: "LIC-2"})

      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end

    test "two differently-named organizations that slugify to the same base still get different slugs" do
      # Names must be unique (enforced above), but two *distinct* names can
      # still slugify to the same base once punctuation is stripped -- the
      # random suffix is what keeps these from colliding on `slug`, not name
      # uniqueness.
      attrs = %{name: "Acme Pharmacy!", license_number: "LIC-1"}
      other_attrs = %{name: "Acme Pharmacy?", license_number: "LIC-2"}

      assert {:ok, first} = Organizations.create_organization(attrs)
      assert {:ok, second} = Organizations.create_organization(other_attrs)

      assert first.slug =~ ~r/^acme-pharmacy-[0-9a-f]{4}$/
      assert second.slug =~ ~r/^acme-pharmacy-[0-9a-f]{4}$/
      assert first.slug != second.slug
    end

    test "enforces slug uniqueness when a slug is given explicitly" do
      organization_fixture(%{slug: "acme"})

      assert {:error, changeset} =
               Organizations.create_organization(%{
                 name: "Other Pharmacy",
                 slug: "acme",
                 license_number: "LIC-2"
               })

      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "get_organization!/1" do
    test "returns the organization with the given id" do
      organization = organization_fixture()
      assert Organizations.get_organization!(organization.id).id == organization.id
    end
  end

  describe "signup/2" do
    test "creates an organization, a default site, and its first admin user in one transaction" do
      org_attrs = %{name: "Acme Pharmacy", license_number: "LIC-1"}
      admin_attrs = valid_user_attributes(%{name: "Jane Admin"})

      assert {:ok, %{organization: organization, site: site, user: user}} =
               Organizations.signup(org_attrs, admin_attrs)

      assert organization.name == "Acme Pharmacy"
      assert organization.license_number == "LIC-1"
      assert organization.slug =~ ~r/^acme-pharmacy-[0-9a-f]{4}$/
      assert site.organization_id == organization.id
      assert site.name == organization.name
      assert site.site_type == :pharmacy
      assert user.organization_id == organization.id
      assert user.role == :admin
      assert user.name == "Jane Admin"
    end

    test "rolls back the whole signup if the admin user is invalid" do
      org_attrs = %{name: "Acme Pharmacy", license_number: "LIC-1"}

      assert {:error, %Ecto.Changeset{}} = Organizations.signup(org_attrs, %{})
      refute Repo.get_by(Organization, name: "Acme Pharmacy")

      # The organization and default site are both created before the admin
      # user step runs (§2.3.1 order: organization -> site -> admin), so this
      # is the case that actually proves the *site* insert gets undone too,
      # not just the organization — the acceptance criterion is "rolls back
      # organization and site creation", not organization alone.
      assert Repo.all(Site) == []
    end

    test "rolls back the whole signup if the admin's email is already taken" do
      existing = user_fixture()
      site_count_before = Repo.aggregate(Site, :count)

      org_attrs = %{name: "Brand New Pharmacy", license_number: "LIC-9"}
      admin_attrs = valid_user_attributes(%{email: existing.email})

      assert {:error, %Ecto.Changeset{}} = Organizations.signup(org_attrs, admin_attrs)
      refute Repo.get_by(Organization, name: "Brand New Pharmacy")
      assert Repo.aggregate(Site, :count) == site_count_before
    end

    test "rolls back the whole signup if the organization name is already taken" do
      organization_fixture(%{name: "Existing Pharmacy"})
      site_count_before = Repo.aggregate(Site, :count)

      org_attrs = %{name: "Existing Pharmacy", license_number: "LIC-9"}
      admin_attrs = valid_user_attributes()

      assert {:error, %Ecto.Changeset{}} = Organizations.signup(org_attrs, admin_attrs)
      refute Repo.get_by(ThamaniDawa.Accounts.User, email: admin_attrs.email)
      assert Repo.aggregate(Site, :count) == site_count_before
    end

    test "rolls back the whole signup if the organization is invalid" do
      admin_attrs = valid_user_attributes()

      assert {:error, %Ecto.Changeset{}} = Organizations.signup(%{}, admin_attrs)
      refute Repo.get_by(ThamaniDawa.Accounts.User, email: admin_attrs.email)
    end
  end
end
