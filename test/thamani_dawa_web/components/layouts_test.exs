defmodule ThamaniDawaWeb.LayoutsTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.DistributorFixtures
  import ThamaniDawa.ManufacturerFixtures
  import ThamaniDawa.SitesFixtures

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawaWeb.Layouts

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

      assert has_element?(lv, "#sidebar-account-dropdown #account-settings", "Account settings")
      assert has_element?(lv, "#sidebar-account-dropdown #account-help-docs", "Help & docs")
      assert has_element?(lv, "#sidebar-account-dropdown #start-product-tour", "Product tour")

      assert has_element?(
               lv,
               "#sidebar-account-dropdown #account-shortcuts",
               "Keyboard shortcuts"
             )

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

    test "collapsed rail keeps the compact mark and labelled nav items", %{
      conn: conn,
      admin: admin
    } do
      site_fixture(%{organization_id: admin.organization_id, name: "HQ"})
      site_fixture(%{organization_id: admin.organization_id, name: "Branch"})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/sites")

      assert has_element?(
               lv,
               "#sidebar-brand-logo.td-br-word[src='/images/logo-transparent.png']"
             )

      assert has_element?(lv, "img.td-br-mark[src='/images/logo-mark.png']")

      assert has_element?(
               lv,
               "a.td-nav-item[aria-label='Sites'][data-tooltip='Sites'][href='/org/sites']"
             )

      assert has_element?(
               lv,
               "a.td-nav-item[aria-label='Team'][data-tooltip='Team'][href='/org/team']"
             )

      assert has_element?(lv, "#site-switch-trigger[data-tooltip]")
    end
  end

  describe "role-gated sidebar links (manufacturer portal)" do
    @admin_only_paths ~w(/manufacturer/mobile-users /manufacturer/api-keys /manufacturer/settings)

    setup %{conn: conn} do
      organization = manufacturer_organization_fixture()
      site = manufacturing_site_fixture(organization.id)

      staff =
        manufacturer_user_fixture(%{organization_id: organization.id, site_id: site.id})

      manager = user_fixture(%{organization_id: organization.id})
      manager = switch_site(manager, site.id)

      {:ok, staff_conn: log_in_user(conn, staff), manager_conn: log_in_user(conn, manager)}
    end

    test "an admin sees the admin-only links, the account menu item and palette rows", %{
      manager_conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/manufacturer")

      for path <- @admin_only_paths do
        assert has_element?(lv, "a.td-nav-item[href='#{path}']")
      end

      assert has_element?(lv, "a.td-nav-item[href='/manufacturer/epcis']")
      assert has_element?(lv, ".td-nav-group-label", "Account")
      assert has_element?(lv, "#account-org-settings[href='/manufacturer/settings']")
      assert has_element?(lv, "#td-command-palette a[href='/manufacturer/mobile-users']")
      assert has_element?(lv, "#td-command-palette a[href='/manufacturer/api-keys']")
    end

    test "a manufacturer-role user who is not an admin does not", %{staff_conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/manufacturer")

      for path <- @admin_only_paths do
        refute has_element?(lv, "a.td-nav-item[href='#{path}']")
      end

      refute has_element?(lv, "#account-org-settings")
      refute has_element?(lv, "#td-command-palette a[href='/manufacturer/mobile-users']")
      refute has_element?(lv, "#td-command-palette a[href='/manufacturer/api-keys']")

      # Pages the router lets any manufacturer open stay in the nav.
      assert has_element?(lv, "a.td-nav-item[href='/manufacturer/products']")
      assert has_element?(lv, "a.td-nav-item[href='/manufacturer/epcis']")
      assert has_element?(lv, ".td-nav-group-label", "Account")
    end

    test "a group whose links are all hidden loses its label" do
      staff = Scope.for_user(manufacturer_user_fixture())
      admin = Scope.for_user(user_fixture())

      groups = [
        {"Manufacturer", [{"Products", "package", "/manufacturer/products"}]},
        {"Account",
         [
           {"API keys", "key", "/manufacturer/api-keys"},
           {"Org settings", "gear", "/manufacturer/settings"}
         ]}
      ]

      assert [{"Manufacturer", [_]}] = Layouts.accessible_nav_groups(staff, groups)

      assert [{"Manufacturer", [_]}, {"Account", [_, _]}] =
               Layouts.accessible_nav_groups(admin, groups)
    end
  end

  describe "role-gated sidebar links (distributor portal)" do
    test "a distributor-role user who is not an admin sees no admin-only links", %{conn: conn} do
      staff = distributor_user_fixture()

      {:ok, lv, _html} = live(log_in_user(conn, staff), ~p"/distributor")

      for path <- ~w(/distributor/billing /distributor/mobile-users /distributor/api-keys
                     /distributor/settings /distributor/epcis /org/sites) do
        refute has_element?(lv, "a.td-nav-item[href='#{path}']")
      end

      refute has_element?(lv, "#account-org-settings")
      assert has_element?(lv, "a.td-nav-item[href='/distributor/shipments']")
    end
  end

  describe "org portal" do
    test "an admin keeps every management link and Org settings", %{conn: conn, admin: admin} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/dashboard")

      for path <- ~w(/org/team /org/mobile-users /org/api-keys /org/epcis /org/settings) do
        assert has_element?(lv, "a.td-nav-item[href='#{path}']")
      end

      assert has_element?(lv, "#account-org-settings[href='/org/settings']")
    end
  end

  describe "account settings" do
    test "the account menu opens a modal that saves the name and emails a reset link", %{
      conn: conn,
      admin: admin
    } do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/sites")

      assert has_element?(lv, "#account-settings-modal", "Account settings")
      assert has_element?(lv, "#account-settings-form")
      assert has_element?(lv, "#account-settings-send-reset", "Send reset link")

      lv
      |> form("#account-settings-form", user: %{name: "Amina Otieno"})
      |> render_submit()

      assert_redirect(lv, ~p"/org/sites")

      {:ok, lv, html} = live(log_in_user(conn, admin), ~p"/org/sites")
      assert html =~ "Amina Otieno"
      assert has_element?(lv, "#sidebar-profile", "Amina Otieno")

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/sites")

      lv
      |> element("#account-settings-send-reset")
      |> render_click()

      assert_redirect(lv, ~p"/org/sites")

      assert_email_sent(fn email ->
        Enum.any?(email.to, fn {_name, addr} -> addr == admin.email end) and
          (email.text_body || email.html_body || "") =~ "reset-password"
      end)
    end
  end

  defp switch_site(user, site_id) do
    {:ok, user} = Accounts.switch_current_site(Scope.for_user(user), site_id)
    user
  end

  defp nav_order_index(html, id) do
    {index, _length} = :binary.match(html, id)
    index
  end
end
