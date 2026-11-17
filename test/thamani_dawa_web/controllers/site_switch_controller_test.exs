defmodule ThamaniDawaWeb.SiteSwitchControllerTest do
  @moduledoc """
  The site switch is the portal chooser: after picking, the user is
  redirected to the panel the picked site offers — a distribution site to
  distribution operations, a pharmacy site to the pharmacy, a lab-only
  site to the lab, and the organization entry (an empty site) to the org
  dashboard. It never sends them to the page they happened to be on.
  """

  use ThamaniDawaWeb.ConnCase, async: true

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.SitesFixtures

  alias ThamaniDawa.Accounts

  describe "PATCH /switch-site" do
    test "picking between a lab and a pharmacy site lands in each portal", %{conn: conn} do
      admin = user_fixture()
      org = admin.organization_id

      pharmacy_site = site_fixture(%{organization_id: org, activities: [:pharmacy]})
      lab_site = site_fixture(%{organization_id: org, activities: [:laboratory]})

      conn = log_in_user(conn, admin)

      conn = patch(conn, ~p"/switch-site", %{"site_id" => to_string(lab_site.id)})

      assert redirected_to(conn) == "/lab"

      conn = patch(conn, ~p"/switch-site", %{"site_id" => to_string(pharmacy_site.id)})

      assert redirected_to(conn) == "/pharmacy"
    end

    test "a distribution site lands in distribution operations", %{conn: conn} do
      org = organization_fixture(%{operating_models: [:distributor]})
      admin = user_fixture(%{organization_id: org.id})

      site = site_fixture(%{organization_id: org.id, activities: [:distribution]})

      conn = log_in_user(conn, admin)

      conn = patch(conn, ~p"/switch-site", %{"site_id" => to_string(site.id)})

      assert redirected_to(conn) == "/distributor"
    end

    test "an empty site id — the organization entry — lands on the org dashboard", %{conn: conn} do
      admin = user_fixture()
      site_fixture(%{organization_id: admin.organization_id})

      conn = log_in_user(conn, admin)

      conn = patch(conn, ~p"/switch-site", %{"site_id" => ""})

      assert redirected_to(conn) == "/org/dashboard"
    end

    test "a site the user is not assigned to is refused, keeping the current context", %{
      conn: conn
    } do
      admin = user_fixture()

      assigned =
        site_fixture(%{organization_id: admin.organization_id, activities: [:pharmacy]})

      other_org = organization_fixture()
      stranger_site = site_fixture(%{organization_id: other_org.id, activities: [:pharmacy]})

      conn = log_in_user(conn, admin)
      conn = patch(conn, ~p"/switch-site", %{"site_id" => to_string(assigned.id)})
      assert redirected_to(conn) == "/pharmacy"

      conn = patch(conn, ~p"/switch-site", %{"site_id" => to_string(stranger_site.id)})

      assert redirected_to(conn) == "/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You're not assigned to that site."

      assert Accounts.get_user!(admin.organization_id, admin.id).current_site_id == assigned.id
    end

    test "an unauthenticated visitor is sent to login", %{conn: conn} do
      conn = patch(conn, ~p"/switch-site", %{"site_id" => ""})

      assert redirected_to(conn) == "/login"
    end
  end
end
