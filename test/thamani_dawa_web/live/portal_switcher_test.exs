defmodule ThamaniDawaWeb.PortalSwitcherTest do
  @moduledoc """
  Exercises the sidebar's portal switcher: an account that can reach more than
  one portal gets one entry per portal, everyone else sees no switcher at all.
  """

  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.SitesFixtures

  describe "multi-role staff" do
    setup %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id, activities: [:pharmacy]})

      admin_pharmacist =
        staff_fixture(%{
          organization_id: admin.organization_id,
          invited_by_id: admin.id,
          roles: [:admin, :pharmacist],
          site_id: site.id
        })

      %{conn: log_in_user(conn, admin_pharmacist)}
    end

    test "see a switcher listing every portal their roles reach", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/org/dashboard")

      assert has_element?(view, "#portal-switch")
      assert has_element?(view, "#portal-switch", "Workspace")
      assert has_element?(view, "#portal-switch-option-admin[href='/org/dashboard']")
      assert has_element?(view, "#portal-switch-option-admin", "Manage organization")
      assert has_element?(view, "#portal-switch-option-pharmacy[href='/pharmacy']")
      assert has_element?(view, "#portal-switch-option-pharmacy", "Dispensing and sales")
    end

    test "see the portal they are in marked as active", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pharmacy")

      assert has_element?(view, "#portal-switch-option-pharmacy .hero-check")
      refute has_element?(view, "#portal-switch-option-admin .hero-check")
    end
  end

  describe "single-role staff" do
    test "a pharmacist sees no switcher", %{conn: conn} do
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

      refute has_element?(view, "#portal-switch")
    end

    test "an admin sees no switcher", %{conn: conn} do
      admin = user_fixture()

      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/org/dashboard")

      refute has_element?(view, "#portal-switch")
    end
  end

  describe "combined pharmacy/lab staff" do
    test "get one entry for the portal family, so no switcher", %{conn: conn} do
      admin = user_fixture()

      site =
        site_fixture(%{
          organization_id: admin.organization_id,
          activities: [:pharmacy, :laboratory]
        })

      pharma_lab =
        staff_fixture(%{
          organization_id: admin.organization_id,
          invited_by_id: admin.id,
          roles: [:pharmacist, :lab_technician],
          site_id: site.id
        })

      {:ok, view, _html} = live(log_in_user(conn, pharma_lab), ~p"/pharmacy")

      refute has_element?(view, "#portal-switch")
    end
  end
end
