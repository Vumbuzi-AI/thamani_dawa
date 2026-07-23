defmodule ThamaniDawaWeb.AdminRoutesTest do
  @moduledoc """
  Exercises the actual router/live_session guard on every `/org/*` screen
  (§7) rather than relying on nav links being hidden or trusting that
  router.ex grouped every admin route into the same live_session — an admin
  must reach each one, and a pharmacist/lab_technician/deactivated-admin/
  anonymous visitor must be bounced away, for real, through the route
  itself.
  """

  use ThamaniDawaWeb.ConnCase, async: true

  import Ecto.Changeset
  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.SitesFixtures

  alias ThamaniDawa.Repo
  alias ThamaniDawaWeb.UserAuth

  for path <- ["/org/team", "/org/team/new", "/org/sites", "/org/sites/new"] do
    describe "GET #{path}" do
      @path path

      test "an admin can reach it", %{conn: conn} do
        admin = user_fixture()
        conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(admin)

        assert {:ok, _view, _html} = live(conn, @path)
      end

      test "a pharmacist is redirected away", %{conn: conn} do
        pharmacist = staff_fixture(%{role: :pharmacist})
        conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(pharmacist)

        assert {:error, {:redirect, %{to: "/"}}} = live(conn, @path)
      end

      test "a lab technician is redirected away", %{conn: conn} do
        lab_technician = staff_fixture(%{role: :lab_technician})
        conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(lab_technician)

        assert {:error, {:redirect, %{to: "/"}}} = live(conn, @path)
      end

      test "combined pharmacy/lab staff are redirected away", %{conn: conn} do
        pharma_lab = staff_fixture(%{role: :pharma_lab})
        conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(pharma_lab)

        assert {:error, {:redirect, %{to: "/"}}} = live(conn, @path)
      end

      test "a deactivated admin is redirected away", %{conn: conn} do
        admin = user_fixture()
        {:ok, deactivated} = admin |> change(is_active: false) |> Repo.update()
        conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(deactivated)

        assert {:error, {:redirect, %{to: "/"}}} = live(conn, @path)
      end

      test "an anonymous visitor is redirected away", %{conn: conn} do
        assert {:error, {:redirect, %{to: "/"}}} = live(conn, @path)
      end
    end
  end

  # A dynamic segment (`:id`), so it can't share the static-path loop above
  # -- but it's the one admin route that also proves the guard runs *before*
  # `Sites.get_site!/2` in `apply_action(:edit, ...)`, not after: a
  # non-admin never reaches the point where a missing/foreign site id could
  # even raise.
  describe "GET /org/sites/:id/edit" do
    test "an admin can reach it", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id})
      conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(admin)

      assert {:ok, _view, _html} = live(conn, ~p"/org/sites/#{site.id}/edit")
    end

    test "a pharmacist is redirected away", %{conn: conn} do
      pharmacist = staff_fixture(%{role: :pharmacist})
      site = site_fixture(%{organization_id: pharmacist.organization_id})
      conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(pharmacist)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/org/sites/#{site.id}/edit")
    end

    test "a lab technician is redirected away", %{conn: conn} do
      lab_technician = staff_fixture(%{role: :lab_technician})
      site = site_fixture(%{organization_id: lab_technician.organization_id})
      conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(lab_technician)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/org/sites/#{site.id}/edit")
    end

    test "a deactivated admin is redirected away", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id})
      {:ok, deactivated} = admin |> change(is_active: false) |> Repo.update()
      conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(deactivated)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/org/sites/#{site.id}/edit")
    end

    test "an anonymous visitor is redirected away", %{conn: conn} do
      site = site_fixture()

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/org/sites/#{site.id}/edit")
    end
  end
end
