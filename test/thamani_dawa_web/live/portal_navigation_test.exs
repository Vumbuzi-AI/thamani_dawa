defmodule ThamaniDawaWeb.PortalNavigationTest do
  @moduledoc """
  Exercises the flattened sidebar nav. There is no cross-portal switcher:
  the current site's activities decide which operations panels exist in the
  nav, the user's roles decide which of those panels they can work, and a
  combined pharmacy+lab site simply shows both panels stacked in one nav.
  Admins see org management (Sites/Products/Suppliers/Team) only in the
  "Manage organization" context (no site selected) — not while drilled
  into a specific site's operations.
  """

  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.SitesFixtures

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Accounts.Scope

  describe "combined pharmacy/lab staff" do
    test "at a combined site, both panels are stacked in one nav", %{conn: conn} do
      %{conn: conn} = combined_staff_at(conn, [:pharmacy, :laboratory])

      {:ok, view, _html} = live(conn, ~p"/pharmacy")

      assert has_element?(view, "span[id='nav-label-/pharmacy']")
      assert has_element?(view, "span[id='nav-label-/lab']")
    end

    test "at a combined site, both panels are also stacked in the lab shell", %{conn: conn} do
      %{conn: conn} = combined_staff_at(conn, [:pharmacy, :laboratory])

      {:ok, view, _html} = live(conn, ~p"/lab")

      assert has_element?(view, "span[id='nav-label-/lab']")
      assert has_element?(view, "span[id='nav-label-/pharmacy']")
    end

    test "at a lab-only site, only the lab panel appears", %{conn: conn} do
      %{conn: conn} = combined_staff_at(conn, [:laboratory])

      {:ok, view, _html} = live(conn, ~p"/lab")

      assert has_element?(view, "span[id='nav-label-/lab']")
      refute has_element?(view, "span[id='nav-label-/pharmacy']")
    end

    test "at a pharmacy-only site, only the pharmacy panel appears", %{conn: conn} do
      %{conn: conn} = combined_staff_at(conn, [:pharmacy])

      {:ok, view, _html} = live(conn, ~p"/pharmacy")

      assert has_element?(view, "span[id='nav-label-/pharmacy']")
      refute has_element?(view, "span[id='nav-label-/lab']")
    end
  end

  describe "single-role staff" do
    test "a pharmacist sees only the pharmacy panel", %{conn: conn} do
      %{conn: conn} = staff_at(conn, [:pharmacist], [:pharmacy])

      {:ok, view, _html} = live(conn, ~p"/pharmacy")

      assert has_element?(view, "span[id='nav-label-/pharmacy']")
      refute has_element?(view, "span[id='nav-label-/lab']")
    end

    test "a lab technician sees only the lab panel", %{conn: conn} do
      %{conn: conn} = staff_at(conn, [:lab_technician], [:laboratory])

      {:ok, view, _html} = live(conn, ~p"/lab")

      assert has_element?(view, "span[id='nav-label-/lab']")
      refute has_element?(view, "span[id='nav-label-/pharmacy']")
    end
  end

  describe "admins carry org management into site context" do
    test "an admin at a pharmacy site sees only that site's panel, not org management", %{
      conn: conn
    } do
      admin = user_fixture()

      site =
        site_fixture(%{organization_id: admin.organization_id, activities: [:pharmacy]})

      admin = switch_site(admin, site.id)

      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/pharmacy")

      assert has_element?(view, "span[id='nav-label-/pharmacy']")
      refute has_element?(view, "span[id='nav-label-/org/sites']")
      refute has_element?(view, "span[id='nav-label-/org/team']")
      refute has_element?(view, "span[id='nav-label-/lab']")
    end

    test "an admin in org context sees org operations plus org management", %{conn: conn} do
      admin = user_fixture()

      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/org/dashboard")

      assert has_element?(view, "span[id='nav-label-/org/dashboard']")
      assert has_element?(view, "span[id='nav-label-/org/sites']")
      assert has_element?(view, "span[id='nav-label-/org/settings']")
      refute has_element?(view, "span[id='nav-label-/pharmacy']")
    end
  end

  describe "distributor staff" do
    test "see distribution operations and nothing org-management-shaped", %{conn: conn} do
      %{conn: conn} = distributor_staff_at(conn, [:distributor])

      {:ok, view, _html} = live(conn, ~p"/distributor")

      assert has_element?(view, "#distributor-nav-toggle[aria-expanded='false']")
      assert has_element?(view, "#distributor-nav-items.hidden")
      assert has_element?(view, "span[id='nav-label-/distributor']")
      assert has_element?(view, "span[id='nav-label-/distributor/shipments']")
      refute has_element?(view, "span[id='nav-label-/org/sites']")
      refute has_element?(view, "span[id='nav-label-/distributor/billing']")
    end

    test "an admin at a distribution site does not see the distributor admin pages", %{
      conn: conn
    } do
      org = organization_fixture(%{operating_models: [:distributor]})
      admin = user_fixture(%{organization_id: org.id})

      site = site_fixture(%{organization_id: org.id, activities: [:distribution]})
      admin = switch_site(admin, site.id)

      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/distributor")

      assert has_element?(view, "span[id='nav-label-/distributor']")
      refute has_element?(view, "span[id='nav-label-/distributor/billing']")
      refute has_element?(view, "span[id='nav-label-/distributor/mobile-users']")
      refute has_element?(view, "span[id='nav-label-/pharmacy']")
    end
  end

  defp combined_staff_at(conn, activities) do
    admin = user_fixture()

    site = site_fixture(%{organization_id: admin.organization_id, activities: activities})

    staff =
      staff_fixture(%{
        organization_id: admin.organization_id,
        invited_by_id: admin.id,
        role: :pharma_lab,
        site_id: site.id
      })

    %{conn: log_in_user(conn, staff)}
  end

  defp staff_at(conn, roles, activities) do
    admin = user_fixture()

    site = site_fixture(%{organization_id: admin.organization_id, activities: activities})

    staff =
      staff_fixture(%{
        organization_id: admin.organization_id,
        invited_by_id: admin.id,
        roles: roles,
        site_id: site.id
      })

    %{conn: log_in_user(conn, staff)}
  end

  defp distributor_staff_at(conn, roles) do
    org = organization_fixture(%{operating_models: [:distributor]})
    admin = user_fixture(%{organization_id: org.id})

    site = site_fixture(%{organization_id: org.id, activities: [:distribution]})

    staff =
      staff_fixture(%{
        organization_id: org.id,
        invited_by_id: admin.id,
        roles: roles,
        site_id: site.id
      })

    %{conn: log_in_user(conn, staff)}
  end

  defp switch_site(admin, site_id) do
    {:ok, admin} = Accounts.switch_current_site(Scope.for_user(admin), site_id)

    admin
  end
end
