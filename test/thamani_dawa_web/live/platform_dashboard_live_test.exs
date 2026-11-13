defmodule ThamaniDawaWeb.PlatformDashboardLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures

  test "a superadmin can see the cross-organization monitoring console", %{conn: conn} do
    organization_fixture(%{name: "Monitoring Health"})
    superadmin = superadmin_fixture()

    {:ok, view, _html} = live(log_in_user(conn, superadmin), ~p"/platform")

    assert has_element?(view, "#platform-dashboard")
    assert has_element?(view, "#platform-overview")
    assert has_element?(view, "#platform-organizations-list")
    assert has_element?(view, "#platform-activity-feed")
    assert has_element?(view, "#platform-prescriptions")
    assert has_element?(view, "a[href='/platform/audit']")
  end

  test "an organization admin cannot enter the platform console", %{conn: conn} do
    admin = user_fixture()

    assert {:error, {:redirect, %{to: "/"}}} = live(log_in_user(conn, admin), ~p"/platform")
  end

  test "an anonymous visitor cannot enter the platform console", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/platform")
  end

  test "a superadmin can open the dedicated audit activity page", %{conn: conn} do
    superadmin = superadmin_fixture()

    {:ok, view, _html} = live(log_in_user(conn, superadmin), ~p"/platform/audit")

    assert has_element?(view, "#platform-audit-list")
  end
end
