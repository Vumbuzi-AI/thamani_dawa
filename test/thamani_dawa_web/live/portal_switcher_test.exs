defmodule ThamaniDawaWeb.PortalSwitcherTest do
  @moduledoc """
  Exercises the sidebar's site picker — the single context switch. The
  organization is one option (admins only, org-wide management), the sites
  the others; picking one lands the user in the panel that site offers.
  Staff only see sites their roles can actually work; anyone with a single
  context sees no picker at all.
  """

  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.SitesFixtures

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Organizations

  describe "admins" do
    setup %{conn: conn} do
      admin = user_fixture()

      pharmacy_site =
        site_fixture(%{
          organization_id: admin.organization_id,
          name: "Branch A",
          activities: [:pharmacy]
        })

      lab_site =
        site_fixture(%{
          organization_id: admin.organization_id,
          name: "Branch B",
          activities: [:laboratory]
        })

      %{
        conn: log_in_user(conn, admin),
        admin: admin,
        pharmacy_site: pharmacy_site,
        lab_site: lab_site
      }
    end

    test "groups the organization context separately from sites", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/org/sites")

      assert has_element?(view, "#site-switch-form")
      assert has_element?(view, "#site-switch-trigger")
      assert has_element?(view, "#site-switch-organization-heading", "Organization")
      assert has_element?(view, "#site-switch-sites-heading", "Sites")
      assert has_element?(view, "#site-switch-org", "All sites")
      assert has_element?(view, "#site-switch-dropdown button", "Branch A")
      assert has_element?(view, "#site-switch-dropdown button", "Branch B")
      assert has_element?(view, "#site-switch-dropdown button", "Pharmacy")
      assert has_element?(view, "#site-switch-dropdown button", "Lab")
    end

    test "the organization entry makes the all-sites scope explicit", %{
      conn: conn,
      admin: admin
    } do
      organization = Organizations.get_organization!(admin.organization_id)

      {:ok, view, _html} = live(conn, ~p"/org/sites")

      assert has_element?(view, "#site-switch-org", "All sites")
      assert has_element?(view, "#site-switch-org", organization.name)
      refute has_element?(view, "#site-switch-org", "Manage organization")
    end

    test "in org context, the organization entry is marked active", %{
      conn: conn,
      lab_site: lab_site
    } do
      {:ok, view, _html} = live(conn, ~p"/org/sites")

      assert has_element?(view, "#site-switch-org .hero-check")
      refute has_element?(view, "#site-switch-option-#{lab_site.id} .hero-check")
    end

    test "after picking a site, that site's entry is marked active", %{
      conn: conn,
      lab_site: lab_site
    } do
      admin = user_fixture(%{organization_id: lab_site.organization_id})
      {:ok, _admin} = Accounts.switch_current_site(Scope.for_user(admin), lab_site.id)

      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/org/sites")

      assert has_element?(view, "#site-switch-option-#{lab_site.id} .hero-check")
      refute has_element?(view, "#site-switch-org .hero-check")
    end
  end

  describe "multi-site staff" do
    test "see the site picker listing their assigned sites, without the organization entry", %{
      conn: conn
    } do
      admin = user_fixture()
      org = admin.organization_id

      first_pharmacy =
        site_fixture(%{organization_id: org, name: "Chemist One", activities: [:pharmacy]})

      second_pharmacy =
        site_fixture(%{organization_id: org, name: "Chemist Two", activities: [:pharmacy]})

      _lab_site = site_fixture(%{organization_id: org, name: "Clinic", activities: [:laboratory]})

      pharmacist =
        staff_fixture(%{
          organization_id: org,
          invited_by_id: admin.id,
          roles: [:pharmacist],
          site_ids: [first_pharmacy.id, second_pharmacy.id]
        })

      {:ok, view, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy")

      assert has_element?(view, "#site-switch-form")
      assert has_element?(view, "#site-switch-sites-heading", "Your sites")
      assert has_element?(view, "#site-switch-dropdown button", "Chemist One")
      assert has_element?(view, "#site-switch-dropdown button", "Chemist Two")
      refute has_element?(view, "#site-switch-dropdown button", "Clinic")
      refute has_element?(view, "#site-switch-org")
    end
  end

  describe "single-context accounts" do
    test "a staff member assigned one site sees no picker", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id, activities: [:pharmacy]})

      pharmacist =
        staff_fixture(%{
          organization_id: admin.organization_id,
          invited_by_id: admin.id,
          roles: [:pharmacist],
          site_id: site.id
        })

      {:ok, view, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy")

      refute has_element?(view, "#site-switch-form")
    end

    test "an admin of a site-less organization sees no picker", %{conn: conn} do
      admin = user_fixture()

      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/org/dashboard")

      refute has_element?(view, "#site-switch-form")
    end
  end

  describe "incompatible site assignments" do
    test "are rejected at invite time, so a role can never strand a staff member", _conn do
      admin = user_fixture()
      org = admin.organization_id

      warehouse_site = site_fixture(%{organization_id: org, activities: [:distribution]})

      assert {:error, changeset} =
               Accounts.invite_user(org, admin.id, %{
                 name: "Stray Pharmacist",
                 email: "stray@example.com",
                 roles: ["pharmacist"],
                 site_ids: [to_string(warehouse_site.id)]
               })

      assert {:sites, {"can't include" <> _, _}} =
               Enum.find(changeset.errors, &match?({:sites, _}, &1))
    end
  end
end
