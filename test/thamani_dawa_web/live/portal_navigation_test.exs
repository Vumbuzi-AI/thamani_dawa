defmodule ThamaniDawaWeb.PortalNavigationTest do
  @moduledoc """
  Exercises the shared sidebar shells' cross-portal navigation. Combined
  pharmacy/lab staff must be able to hop between both portals from either
  shell (via stable DOM IDs), while single-role staff never gain a link to
  the other operational portal.
  """

  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures

  describe "combined pharmacy/lab staff" do
    setup %{conn: conn} do
      admin = user_fixture()

      pharma_lab =
        staff_fixture(%{
          organization_id: admin.organization_id,
          invited_by_id: admin.id,
          role: :pharma_lab
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

  describe "single-role staff" do
    setup %{conn: conn} do
      %{admin: user_fixture(), conn: conn}
    end

    test "a pharmacist gets no cross-portal link", %{admin: admin, conn: conn} do
      pharmacist =
        staff_fixture(%{
          organization_id: admin.organization_id,
          invited_by_id: admin.id,
          role: :pharmacist
        })

      {:ok, view, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy")

      refute has_element?(view, "#sidebar-portal-switch")
      refute has_element?(view, "#portal-link-lab")
    end

    test "a lab technician gets no cross-portal link", %{admin: admin, conn: conn} do
      lab_technician =
        staff_fixture(%{
          organization_id: admin.organization_id,
          invited_by_id: admin.id,
          role: :lab_technician
        })

      {:ok, view, _html} = live(log_in_user(conn, lab_technician), ~p"/lab")

      refute has_element?(view, "#sidebar-portal-switch")
      refute has_element?(view, "#portal-link-pharmacy")
    end
  end
end
