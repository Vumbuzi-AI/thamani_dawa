defmodule ThamaniDawaWeb.OrgMobileUserLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures

  alias ThamaniDawa.GS1.MemberApiStub
  alias ThamaniDawa.Organizations
  alias ThamaniDawaWeb.UserAuth

  defp log_in(conn, user), do: conn |> init_test_session(%{}) |> UserAuth.log_in_user(user)

  defp with_gs1_key(admin) do
    {:ok, _organization} =
      admin.organization_id
      |> Organizations.get_organization!()
      |> Organizations.set_gs1_api_key("gs1-secret")

    admin
  end

  defp unique_username(prefix), do: "#{prefix}#{System.unique_integer([:positive])}"

  defp stub_user_by_username(username) do
    {:ok, body} = MemberApiStub.post_mobile_users("list", %{})
    users = body["mobile_users"]

    Enum.find(users, &(&1["username"] == username))
  end

  test "asks for a GS1 key when the organization has none", %{conn: conn} do
    {:ok, view, _html} = live(log_in(conn, user_fixture()), ~p"/org/mobile-users")

    assert has_element?(view, "#mobile-users-unconfigured")
    refute has_element?(view, "#new-mobile-user")
  end

  test "adds a manufacturing aggregation-only user through GS1", %{conn: conn} do
    admin = user_fixture() |> with_gs1_key()
    username = unique_username("agg")

    {:ok, view, _html} = live(log_in(conn, admin), ~p"/org/mobile-users/new")

    view
    |> form("#mobile-user-modal-form",
      mobile_user: %{
        name: "Agg User",
        username: username,
        email: "#{username}@example.com",
        role: "manufacturing",
        access_scope: "aggregation_only"
      }
    )
    |> render_submit()

    user = stub_user_by_username(username)
    assert user["role"] == "manufacturing"
    assert user["access_scope"] == "aggregation_only"
    assert has_element?(view, "#mobile-user-#{user["id"]}")
  end

  test "a distribution user never gets aggregation-only access", %{conn: conn} do
    admin = user_fixture() |> with_gs1_key()
    username = unique_username("dist")

    {:ok, view, _html} = live(log_in(conn, admin), ~p"/org/mobile-users/new")

    view
    |> form("#mobile-user-modal-form", mobile_user: %{role: "distribution"})
    |> render_change()

    refute has_element?(view, "#mobile-user-modal-form select[name='mobile_user[access_scope]']")

    view
    |> form("#mobile-user-modal-form",
      mobile_user: %{
        name: "Dist User",
        username: username,
        email: "#{username}@example.com",
        role: "distribution"
      }
    )
    |> render_submit()

    user = stub_user_by_username(username)
    assert user["role"] == "distribution"
    assert user["access_scope"] == "full"
  end

  test "shows GS1 validation errors on the form", %{conn: conn} do
    admin = user_fixture() |> with_gs1_key()
    {:ok, view, _html} = live(log_in(conn, admin), ~p"/org/mobile-users/new")

    html =
      view
      |> form("#mobile-user-modal-form", mobile_user: %{name: "", username: "", email: ""})
      |> render_submit()

    assert html =~ "can&#39;t be blank"
    assert has_element?(view, "#mobile-user-modal-form")
  end

  test "resends a PIN and deactivates then reactivates a user", %{conn: conn} do
    admin = user_fixture() |> with_gs1_key()
    username = unique_username("cycle")

    {:ok, %{"mobile_user" => %{"id" => id}}} =
      MemberApiStub.post_mobile_users("create", %{
        "name" => "Cycle User",
        "username" => username,
        "email" => "#{username}@example.com",
        "role" => "manufacturing"
      })

    {:ok, view, _html} = live(log_in(conn, admin), ~p"/org/mobile-users")

    view |> element("#resend-pin-#{id}") |> render_click()

    assert view |> element("#resend-pin-modal button", "Resend invite") |> render_click() =~
             "new PIN was emailed"

    view |> element("#deactivate-mobile-user-#{id}") |> render_click()
    view |> element("#deactivate-mobile-user-modal button", "Deactivate") |> render_click()
    assert has_element?(view, "#activate-mobile-user-#{id}")
    refute stub_user_by_username(username)["active"]

    view |> element("#activate-mobile-user-#{id}") |> render_click()
    assert has_element?(view, "#deactivate-mobile-user-#{id}")
  end

  test "shows a user who has not used their PIN as invite pending", %{conn: conn} do
    admin = user_fixture() |> with_gs1_key()
    username = unique_username("pending")

    {:ok, %{"mobile_user" => %{"id" => id}}} =
      MemberApiStub.post_mobile_users("create", %{
        "name" => "Pending User",
        "username" => username,
        "email" => "#{username}@example.com",
        "role" => "manufacturing"
      })

    {:ok, view, html} = live(log_in(conn, admin), ~p"/org/mobile-users")

    assert html =~ "Invite pending"
    assert has_element?(view, "#mobile-user-#{id}", "Resend invite")
    refute has_element?(view, "#mobile-user-#{id}", "Resend PIN")
  end

  test "refresh reloads users created on GS1 after the page was loaded", %{conn: conn} do
    admin = user_fixture() |> with_gs1_key()
    username = unique_username("late")

    {:ok, view, _html} = live(log_in(conn, admin), ~p"/org/mobile-users")

    {:ok, %{"mobile_user" => %{"id" => id}}} =
      MemberApiStub.post_mobile_users("create", %{
        "name" => "Late User",
        "username" => username,
        "email" => "#{username}@example.com",
        "role" => "manufacturing"
      })

    refute has_element?(view, "#mobile-user-#{id}")

    html = view |> element("#refresh-mobile-users") |> render_click()

    assert has_element?(view, "#mobile-user-#{id}")
    assert html =~ "Mobile users refreshed."
  end

  test "merge_users keeps users added this session when GS1's list has not returned them" do
    listed = [%{"id" => "listed", "name" => "Listed"}]

    pending = [
      %{"id" => "listed", "name" => "Stale copy"},
      %{"id" => "new", "name" => "Just added"}
    ]

    merged = ThamaniDawaWeb.OrgMobileUserLive.Index.merge_users(listed, pending)

    assert Enum.map(merged, & &1["id"]) == ["listed", "new"]
    assert hd(merged)["name"] == "Listed"
  end
end
