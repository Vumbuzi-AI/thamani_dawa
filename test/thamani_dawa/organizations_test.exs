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
               Organizations.create_organization(%{
                 name: "Acme Pharmacy",
                 license_number: "LIC-1"
               })

      assert organization.name == "Acme Pharmacy"
      assert organization.license_number == "LIC-1"
      assert organization.operating_models == [:pharmacy]
      assert organization.is_active
    end

    test "trims surrounding whitespace from the organization name and license number" do
      assert {:ok, organization} =
               Organizations.create_organization(%{
                 name: "  Mwangaza Pharmacy  ",
                 license_number: "  PPB-TEST-01  "
               })

      assert organization.name == "Mwangaza Pharmacy"
      assert organization.license_number == "PPB-TEST-01"
      assert organization.slug == "mwangaza-pharmacy"
    end

    test "ignores client-supplied server-controlled flags, e.g. is_subscription_active" do
      assert {:ok, organization} =
               Organizations.create_organization(%{
                 name: "Acme Pharmacy",
                 license_number: "LIC-1",
                 is_active: false,
                 is_subscription_active: true,
                 kyc_details: %{"verified" => true}
               })

      assert organization.is_active
      refute organization.is_subscription_active
      assert organization.kyc_details == %{}
    end

    test "requires a name" do
      assert {:error, changeset} =
               Organizations.create_organization(%{license_number: "LIC-1"})

      assert %{name: ["Please enter your organization name"]} = errors_on(changeset)
    end

    test "requires a license number" do
      assert {:error, changeset} = Organizations.create_organization(%{name: "Acme Pharmacy"})
      assert %{license_number: ["Please enter your license number"]} = errors_on(changeset)
    end

    test "auto-generates a slug from the name when none is given" do
      assert {:ok, organization} =
               Organizations.create_organization(%{
                 name: "Acme Pharmacy",
                 license_number: "LIC-1"
               })

      assert organization.slug == "acme-pharmacy"
    end

    test "strips accents when generating a slug" do
      assert {:ok, organization} =
               Organizations.create_organization(%{
                 name: "Café Pharmacy",
                 license_number: "LIC-1"
               })

      assert organization.slug == "cafe-pharmacy"
    end

    test "still auto-generates a slug when the caller passes an explicit blank one" do
      assert {:ok, organization} =
               Organizations.create_organization(%{
                 name: "Acme Pharmacy",
                 slug: "",
                 license_number: "LIC-1"
               })

      assert organization.slug == "acme-pharmacy"
    end

    test "rejects a name that slugifies to nothing" do
      assert {:error, changeset} =
               Organizations.create_organization(%{name: "!!!", license_number: "LIC-1"})

      assert %{name: ["must contain at least one letter or number"]} = errors_on(changeset)
    end

    test "rejects an explicit slug that normalizes to nothing" do
      assert {:error, changeset} =
               Organizations.create_organization(%{
                 name: "Acme Pharmacy",
                 slug: "---",
                 license_number: "LIC-1"
               })

      assert %{name: ["must contain at least one letter or number"]} = errors_on(changeset)
    end

    test "requires a unique name" do
      organization_fixture(%{name: "City Pharmacy"})

      assert {:error, changeset} =
               Organizations.create_organization(%{
                 name: "City Pharmacy",
                 slug: "unrelated-slug",
                 license_number: "LIC-2"
               })

      assert %{name: ["An organization with this name already exists"]} = errors_on(changeset)
    end

    test "enforces slug uniqueness when a slug is given explicitly" do
      organization_fixture(%{slug: "acme"})

      assert {:error, changeset} =
               Organizations.create_organization(%{
                 name: "Other Pharmacy",
                 slug: "acme",
                 license_number: "LIC-2"
               })

      assert %{name: ["An organization with a similar name already exists"]} =
               errors_on(changeset)
    end

    test "rejects names that are case- and punctuation-insensitive duplicates" do
      organization_fixture(%{name: "PharmaPlus"})

      for name <- ["pharmaplus", "Pharma-Plus", "Pharma Plus"] do
        assert {:error, changeset} =
                 Organizations.create_organization(%{
                   name: name,
                   license_number: "LIC-#{System.unique_integer()}"
                 })

        assert %{name: ["An organization with a similar name already exists"]} =
                 errors_on(changeset)
      end
    end

    test "normalizes an explicitly-given slug the same way as an auto-generated one" do
      organization_fixture(%{name: "PharmaPlus"})

      assert {:error, changeset} =
               Organizations.create_organization(%{
                 name: "Other Pharmacy",
                 slug: "Pharma-Plus",
                 license_number: "LIC-2"
               })

      assert %{name: ["An organization with a similar name already exists"]} =
               errors_on(changeset)
    end

    test "rejects a malformed GS1 company prefix" do
      assert {:error, changeset} =
               Organizations.create_organization(%{
                 name: "Acme Pharmacy",
                 license_number: "LIC-1",
                 gs1_company_prefix: "abc123"
               })

      assert %{gs1_company_prefix: ["must be 6 to 10 digits"]} = errors_on(changeset)
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
      org_attrs = %{name: "Acme Pharmacy", license_number: "LIC-1", gs1_company_prefix: "6160001"}
      admin_attrs = valid_user_attributes(%{name: "Jane Admin"})

      assert {:ok, %{organization: organization, site: site, user: user}} =
               Organizations.signup(org_attrs, admin_attrs)

      assert organization.name == "Acme Pharmacy"
      assert organization.license_number == "LIC-1"
      assert organization.gs1_company_prefix == "6160001"
      assert organization.gs1_prefix_verification_status == :pending
      assert organization.slug == "acme-pharmacy"
      assert site.organization_id == organization.id
      assert site.name == organization.name
      assert site.activities == [:pharmacy]
      assert is_nil(site.gln)
      assert user.organization_id == organization.id
      assert user.roles == [:admin]
      assert user.name == "Jane Admin"
    end

    test "requires a GS1 company prefix for a pharmacy organization" do
      assert {:error, changeset} =
               Organizations.signup(
                 %{name: "Acme Pharmacy", license_number: "LIC-1"},
                 valid_user_attributes()
               )

      assert %{gs1_company_prefix: ["Please enter your GS1 company prefix"]} =
               errors_on(changeset)
    end

    test "derives a combined site for pharmacy and laboratory legacy signup" do
      org_attrs = %{
        name: "Acme Health",
        license_number: "LIC-H",
        gs1_company_prefix: "6160001",
        operating_models: [:pharmacy, :laboratory]
      }

      assert {:ok, %{site: site}} = Organizations.signup(org_attrs, valid_user_attributes())
      assert site.activities == [:pharmacy, :laboratory]
    end

    test "rolls back the whole signup if the admin user is invalid" do
      site_count_before = Repo.aggregate(Site, :count)
      org_attrs = %{name: "Acme Pharmacy", license_number: "LIC-1", gs1_company_prefix: "6160001"}

      assert {:error, %Ecto.Changeset{}} = Organizations.signup(org_attrs, %{})
      refute Repo.get_by(Organization, name: "Acme Pharmacy")

      # The organization and default site are both created before the admin
      # user step runs (§2.3.1 order: organization -> site -> admin), so this
      # is the case that actually proves the *site* insert gets undone too,
      # not just the organization — the acceptance criterion is "rolls back
      # organization and site creation", not organization alone.
      assert Repo.aggregate(Site, :count) == site_count_before
    end

    test "rolls back the whole signup if the admin's email is already taken" do
      existing = user_fixture()
      site_count_before = Repo.aggregate(Site, :count)

      org_attrs = %{
        name: "Brand New Pharmacy",
        license_number: "LIC-9",
        gs1_company_prefix: "6160001"
      }

      admin_attrs = valid_user_attributes(%{email: existing.email})

      assert {:error, %Ecto.Changeset{}} = Organizations.signup(org_attrs, admin_attrs)
      refute Repo.get_by(Organization, name: "Brand New Pharmacy")
      assert Repo.aggregate(Site, :count) == site_count_before
    end

    test "rolls back the whole signup if the organization name is already taken" do
      organization_fixture(%{name: "Existing Pharmacy"})
      site_count_before = Repo.aggregate(Site, :count)

      org_attrs = %{
        name: "Existing Pharmacy",
        license_number: "LIC-9",
        gs1_company_prefix: "6160001"
      }

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

  describe "signup/3" do
    test "creates a distributor with a selected warehouse site" do
      org_attrs = %{
        name: "Acme Distribution",
        license_number: "LIC-D",
        gs1_company_prefix: "0614141",
        operating_models: [:distributor]
      }

      site_attrs = %{
        name: "Central Warehouse",
        activities: [:distribution],
        address: "Industrial Area"
      }

      assert {:ok, %{organization: organization, site: site}} =
               Organizations.signup(org_attrs, site_attrs, valid_user_attributes())

      assert organization.operating_models == [:distributor]
      assert site.name == "Central Warehouse"
      assert site.activities == [:distribution]
      assert site.address == "Industrial Area"
    end

    test "requires a GS1 company prefix for a distributor organization" do
      org_attrs = %{
        name: "Acme Distribution",
        license_number: "LIC-D",
        operating_models: [:distributor]
      }

      assert {:error, changeset} =
               Organizations.signup(
                 org_attrs,
                 %{
                   name: "Central Warehouse",
                   activities: [:distribution]
                 },
                 valid_user_attributes()
               )

      assert %{gs1_company_prefix: ["Please enter your GS1 company prefix"]} =
               errors_on(changeset)
    end

    test "requires a GS1 company prefix for a laboratory-only organization" do
      org_attrs = %{
        name: "Acme Labs",
        license_number: "LIC-L",
        operating_models: [:laboratory]
      }

      assert {:error, changeset} =
               Organizations.signup(
                 org_attrs,
                 %{
                   name: "Acme Labs Main",
                   activities: [:laboratory]
                 },
                 valid_user_attributes()
               )

      assert %{gs1_company_prefix: ["Please enter your GS1 company prefix"]} =
               errors_on(changeset)
    end

    test "creates a laboratory-only organization once its GS1 company prefix is given" do
      org_attrs = %{
        name: "Acme Labs",
        license_number: "LIC-L",
        gs1_company_prefix: "6160001",
        operating_models: [:laboratory]
      }

      assert {:ok, %{organization: organization, site: site}} =
               Organizations.signup(
                 org_attrs,
                 %{
                   name: "Acme Labs Main",
                   activities: [:laboratory]
                 },
                 valid_user_attributes()
               )

      assert organization.gs1_company_prefix == "6160001"
      assert organization.gs1_prefix_verification_status == :pending
      assert site.activities == [:laboratory]
    end

    test "rejects a malformed GS1 company prefix" do
      org_attrs = %{
        name: "Acme Distribution",
        license_number: "LIC-D",
        gs1_company_prefix: "xyz",
        operating_models: [:distributor]
      }

      assert {:error, changeset} =
               Organizations.signup(
                 org_attrs,
                 %{
                   name: "Central Warehouse",
                   activities: [:distribution]
                 },
                 valid_user_attributes()
               )

      assert %{gs1_company_prefix: ["must be 6 to 10 digits"]} = errors_on(changeset)
    end

    test "persists the entered site GLN as unverified" do
      org_attrs = %{
        name: "Acme Pharmacy",
        license_number: "LIC-1",
        gs1_company_prefix: "6160001"
      }

      site_attrs = %{
        name: "Acme Main",
        activities: [:pharmacy],
        gln: "6160001000004"
      }

      assert {:ok, %{site: site}} =
               Organizations.signup(org_attrs, site_attrs, valid_user_attributes())

      assert site.gln == "6160001000004"
      assert is_nil(site.gln_verified_at)
      assert is_nil(site.gln_verification_source)
    end

    test "enqueues prefix and GLN verification jobs when identifiers are entered" do
      org_attrs = %{
        name: "Acme Pharmacy",
        license_number: "LIC-1",
        gs1_company_prefix: "6160001"
      }

      site_attrs = %{
        name: "Acme Main",
        activities: [:pharmacy],
        gln: "6160001000004"
      }

      assert {:ok, %{organization: organization, site: site}} =
               Organizations.signup(org_attrs, site_attrs, valid_user_attributes())

      jobs = Repo.all(Oban.Job)
      args = Enum.map(jobs, & &1.args)

      assert %{"organization_id" => organization.id} in args
      assert %{"record" => "site", "id" => site.id} in args
    end

    test "does not enqueue a GLN verification job when no GLN is entered" do
      org_attrs = %{
        name: "Acme Pharmacy",
        license_number: "LIC-1",
        gs1_company_prefix: "6160001"
      }

      site_attrs = %{name: "Acme Main", activities: [:pharmacy]}

      assert {:ok, %{organization: organization}} =
               Organizations.signup(org_attrs, site_attrs, valid_user_attributes())

      args = Enum.map(Repo.all(Oban.Job), & &1.args)
      assert [%{"organization_id" => organization.id}] == args
    end
  end
end
