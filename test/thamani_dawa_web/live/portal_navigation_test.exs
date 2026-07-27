defmodule ThamaniDawaWeb.PortalNavigationTest do
  @moduledoc """
  Exercises the shared sidebar shells' cross-portal navigation. Combined
  pharmacy/lab staff only get a cross-portal switch link while their
  *current site* actually offers both operations — a pharma_lab user
  stationed at a lab-only (or pharmacy-only) site sees just that one side,
  same as single-role staff.
  """

  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.SitesFixtures

  describe "combined pharmacy/lab staff at a combined site" do
    setup %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id, site_type: :pharmacy_lab})

      pharma_lab =
        staff_fixture(%{
          organization_id: admin.organization_id,
          invited_by_id: admin.id,
          role: :pharma_lab,
          site_id: site.id
        })

      %{conn: log_in_user(conn, pharma_lab)}
    end

    test "see a link to the lab portal from the pharmacy shell", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pharmacy")

      assert has_element?(view, "#sidebar-portal-switch")
      assert has_element?(view, "#portal-link-lab")
      refute has_element?(view, "#portal-link-pharmacy")
    end

    test "see a link to the pharmacy portal from the lab shell", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/lab")

      assert has_element?(view, "#sidebar-portal-switch")
      assert has_element?(view, "#portal-link-pharmacy")
      refute has_element?(view, "#portal-link-lab")
    end
  end

  describe "combined pharmacy/lab staff at a single-purpose site" do
    test "at a lab-only site, gets no cross-portal switch from the lab shell", %{conn: conn} do
      admin = user_fixture()
      lab_site = site_fixture(%{organization_id: admin.organization_id, site_type: :lab})

      pharma_lab =
        staff_fixture(%{
          organization_id: admin.organization_id,
          invited_by_id: admin.id,
          role: :pharma_lab,
          site_id: lab_site.id
        })

      {:ok, view, _html} = live(log_in_user(conn, pharma_lab), ~p"/lab")

      refute has_element?(view, "#sidebar-portal-switch")
      refute has_element?(view, "#portal-link-pharmacy")
    end

    test "at a pharmacy-only site, gets no cross-portal switch from the pharmacy shell", %{
      conn: conn
    } do
      admin = user_fixture()

      pharmacy_site =
        site_fixture(%{organization_id: admin.organization_id, site_type: :pharmacy})

      pharma_lab =
        staff_fixture(%{
          organization_id: admin.organization_id,
          invited_by_id: admin.id,
          role: :pharma_lab,
          site_id: pharmacy_site.id
        })

      {:ok, view, _html} = live(log_in_user(conn, pharma_lab), ~p"/pharmacy")

      refute has_element?(view, "#sidebar-portal-switch")
      refute has_element?(view, "#portal-link-lab")
    end
  end

  describe "single-role staff" do
    setup %{conn: conn} do
      %{admin: user_fixture(), conn: conn}
    end

    test "a pharmacist gets no cross-portal link", %{admin: admin, conn: conn} do
      site = site_fixture(%{organization_id: admin.organization_id, site_type: :pharmacy})

      pharmacist =
        staff_fixture(%{
          organization_id: admin.organization_id,
          invited_by_id: admin.id,
          role: :pharmacist,
          site_id: site.id
        })

      {:ok, view, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy")

      refute has_element?(view, "#sidebar-portal-switch")
      refute has_element?(view, "#portal-link-lab")
    end

    test "a lab technician gets no cross-portal link", %{admin: admin, conn: conn} do
      site = site_fixture(%{organization_id: admin.organization_id, site_type: :lab})

      lab_technician =
        staff_fixture(%{
          organization_id: admin.organization_id,
          invited_by_id: admin.id,
          role: :lab_technician,
          site_id: site.id
        })

      {:ok, view, _html} = live(log_in_user(conn, lab_technician), ~p"/lab")

      refute has_element?(view, "#sidebar-portal-switch")
      refute has_element?(view, "#portal-link-pharmacy")
    end
  end
end
