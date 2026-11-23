defmodule ThamaniDawaWeb.LayoutsTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.SitesFixtures

  setup do
    admin = user_fixture()
    {:ok, admin: admin}
  end

  describe "requisitions nav item" do
    test "hidden for a single-site organization", %{conn: conn, admin: admin} do
      site_fixture(%{organization_id: admin.organization_id})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/sites")

      refute has_element?(lv, "span[id='nav-label-/org/requisitions']")
    end

    test "shown once an organization has more than one site", %{conn: conn, admin: admin} do
      site_fixture(%{organization_id: admin.organization_id})
      site_fixture(%{organization_id: admin.organization_id})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/sites")

      assert has_element?(lv, "span[id='nav-label-/org/requisitions']")
    end
  end

  describe "organization sidebar navigation" do
    test "multi-site admins can switch from the organization to a specific branch", %{
      conn: conn,
      admin: admin
    } do
      site_fixture(%{organization_id: admin.organization_id, name: "Branch A"})
      site_fixture(%{organization_id: admin.organization_id, name: "Branch B"})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/sites")

      assert has_element?(lv, "#site-switch-form")
      assert has_element?(lv, "#site-switch-trigger")
      assert has_element?(lv, "#site-switch-organization-heading", "Organization")
      assert has_element?(lv, "#site-switch-sites-heading", "Sites")
      assert has_element?(lv, "#site-switch-org", "All sites")
      assert has_element?(lv, "#site-switch-dropdown button", "Branch A")
      assert has_element?(lv, "#site-switch-dropdown button", "Branch B")
    end

    test "provides mobile navigation controls and identifies the active page", %{
      conn: conn,
      admin: admin
    } do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/sites")

      assert has_element?(
               lv,
               "#mobile-sidebar-toggle[aria-controls='sidebar-aside'][aria-expanded='false']"
             )

      assert has_element?(lv, "#sidebar-backdrop[aria-label='Close navigation']")
      assert has_element?(lv, "#sidebar-aside[aria-label='Organization navigation']")
      assert has_element?(lv, "#sidebar-brand-link[aria-label='Thamani Dawa home']")
      assert has_element?(lv, "#sidebar-brand-logo[src='/images/logo-transparent.png']")

      assert has_element?(
               lv,
               "#sidebar-toggle[aria-controls='sidebar-aside'][aria-expanded='true'][aria-label='Collapse sidebar']"
             )

      assert has_element?(lv, "#sidebar-toggle svg")
      assert has_element?(lv, "a[aria-current='page']", "Sites")
    end

    test "Sites appears immediately above Team in the main nav", %{conn: conn, admin: admin} do
      {:ok, lv, html} = live(log_in_user(conn, admin), ~p"/org/sites")

      assert has_element?(lv, "span[id='nav-label-/org/sites']")
      assert has_element?(lv, "span[id='nav-label-/org/team']")

      assert nav_order_index(html, "nav-label-/org/sites") <
               nav_order_index(html, "nav-label-/org/team")
    end

    test "highlights Sites as active when on the sites page, not Team", %{
      conn: conn,
      admin: admin
    } do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/sites")

      assert has_element?(lv, "a[aria-current='page']", "Sites")
      refute has_element?(lv, "a[aria-current='page']", "Team")
    end

    test "highlights Team as active when on the team page, not Sites", %{
      conn: conn,
      admin: admin
    } do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/team")

      assert has_element?(lv, "a[aria-current='page']", "Team")
      refute has_element?(lv, "a[aria-current='page']", "Sites")
    end

    test "groups help and personal actions in the sidebar footer", %{conn: conn, admin: admin} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/sites")

      assert has_element?(lv, "#sidebar-account-dropdown #start-product-tour", "Product tour")
      assert has_element?(lv, "#sidebar-account-dropdown #account-theme-dark[role=menuitemradio]")

      assert has_element?(
               lv,
               "#sidebar-account-dropdown #account-org-settings[href='/org/settings']"
             )

      refute has_element?(lv, "#dark-mode-switch")
      assert has_element?(lv, "#sidebar-account-card[aria-label='Open account menu']")
      assert has_element?(lv, "#sidebar-profile", "Test User")
      assert has_element?(lv, "#sidebar-account-dropdown #sidebar-logout", "Log out")
    end
  end

  defp nav_order_index(html, id) do
    {index, _length} = :binary.match(html, id)
    index
  end
end
