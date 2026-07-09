defmodule ThamaniDawaWeb.TeamLiveTest do
  @moduledoc """
  Drives the real Team screen form (§ Complete team invite LiveView flow)
  rather than calling `Accounts.invite_user/3` directly, so a future markup
  change (a renamed field, a removed `.input`) breaks a test here instead of
  silently breaking the actual invite flow.

  `user_fixture/1` always produces an admin (`Accounts.register_user/2`
  hardcodes `role: :admin`), which is why every test here can reach
  `/org/team/new` directly without a role check of its own -- the
  admin-only route guard itself (admin allowed, every other role and
  anonymous denied) is exercised end-to-end in `admin_routes_test.exs`,
  not duplicated here.
  """

  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.SitesFixtures

  alias ThamaniDawaWeb.UserAuth

  defp log_in(conn, user), do: conn |> init_test_session(%{}) |> UserAuth.log_in_user(user)

  describe "GET /org/team/new" do
    test "an admin sees the invite form with unique field ids", %{conn: conn} do
      admin = user_fixture()
      assert admin.role == :admin

      {:ok, _view, html} = live(log_in(conn, admin), ~p"/org/team/new")

      assert html =~ ~s(id="invite-form")
      assert html =~ ~s(id="user_name")
      assert html =~ ~s(id="user_email")
      assert html =~ ~s(id="user_role")
      assert html =~ ~s(id="user_site_id")
    end

    test "a pharmacist (non-admin) is redirected away, never sees the form", %{conn: conn} do
      pharmacist = staff_fixture(%{role: :pharmacist})

      assert {:error, {:redirect, %{to: "/"}}} =
               live(log_in(conn, pharmacist), ~p"/org/team/new")
    end
  end

  describe "invite a staff member" do
    test "a successful invite shows a flash and adds the new hire to the staff list", %{
      conn: conn
    } do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id})
      {:ok, view, _html} = live(log_in(conn, admin), ~p"/org/team/new")

      html =
        view
        |> form("#invite-form",
          user: %{
            name: "New Hire",
            email: "new.hire@example.com",
            role: "pharmacist",
            site_id: site.id
          }
        )
        |> render_submit()

      assert html =~ "Invite sent to new.hire@example.com."
      assert html =~ "New Hire"
      assert html =~ "Pharmacist"

      assert_email_sent(to: [{"", "new.hire@example.com"}])
    end

    test "a blank form shows validation errors and does not invite anyone", %{conn: conn} do
      admin = user_fixture()
      {:ok, view, _html} = live(log_in(conn, admin), ~p"/org/team/new")

      html =
        view
        |> form("#invite-form", user: %{name: "", email: "", role: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      refute html =~ "Invite sent to"
    end

    test "an invalid email shows a validation error and does not invite anyone", %{conn: conn} do
      admin = user_fixture()
      {:ok, view, _html} = live(log_in(conn, admin), ~p"/org/team/new")

      html =
        view
        |> form("#invite-form",
          user: %{name: "New Hire", email: "not-an-email", role: "pharmacist"}
        )
        |> render_submit()

      assert html =~ "must have the @ sign and no spaces"
      refute html =~ "Invite sent to"
    end
  end
end
