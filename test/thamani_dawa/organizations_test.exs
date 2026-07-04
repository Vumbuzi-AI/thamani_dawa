defmodule ThamaniDawa.OrganizationsTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Repo

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures

  describe "create_organization/1" do
    test "creates an organization with a name" do
      assert {:ok, organization} = Organizations.create_organization(%{name: "Acme Pharmacy"})
      assert organization.name == "Acme Pharmacy"
      assert organization.is_active
    end

    test "requires a name" do
      assert {:error, changeset} = Organizations.create_organization(%{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "enforces slug uniqueness when a slug is given" do
      organization_fixture(%{slug: "acme"})

      assert {:error, changeset} =
               Organizations.create_organization(%{name: "Other Pharmacy", slug: "acme"})

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
      org_attrs = %{name: "Acme Pharmacy"}
      admin_attrs = valid_user_attributes(%{name: "Jane Admin"})

      assert {:ok, %{organization: organization, site: site, user: user}} =
               Organizations.signup(org_attrs, admin_attrs)

      assert organization.name == "Acme Pharmacy"
      assert site.organization_id == organization.id
      assert site.name == organization.name
      assert site.site_type == :pharmacy
      assert user.organization_id == organization.id
      assert user.role == :admin
      assert user.name == "Jane Admin"
    end

    test "rolls back the whole signup if the admin user is invalid" do
      org_attrs = %{name: "Acme Pharmacy"}

      assert {:error, %Ecto.Changeset{}} = Organizations.signup(org_attrs, %{})
      refute Repo.get_by(Organization, name: "Acme Pharmacy")
    end

    test "rolls back the whole signup if the organization is invalid" do
      admin_attrs = valid_user_attributes()

      assert {:error, %Ecto.Changeset{}} = Organizations.signup(%{}, admin_attrs)
      refute Repo.get_by(ThamaniDawa.Accounts.User, email: admin_attrs.email)
    end
  end
end
