defmodule ThamaniDawaWeb.AcceptInviteLiveTest do
  @moduledoc """
  Covers the acceptance criteria for completing the invite/accept flow (§7):
  a valid token lets a new hire set a password and is invalidated
  immediately after; a reused, expired, or otherwise invalid token fails
  safely (flash + redirect to /login), never a crash.
  """

  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.OrganizationsFixtures

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Accounts.UserToken
  alias ThamaniDawa.Repo

  defp invite_fixture(email) do
    organization = organization_fixture()

    {:ok, invited, encoded_token} =
      Accounts.invite_user(organization.id, nil, %{
        name: "New Hire",
        email: email,
        role: :pharmacist
      })

    %{organization: organization, invited: invited, encoded_token: encoded_token}
  end

  describe "GET /invites/:token" do
    test "a valid token lets the invited user set a password", %{conn: conn} do
      %{organization: organization, invited: invited, encoded_token: encoded_token} =
        invite_fixture("valid@example.com")

      {:ok, view, html} = live(conn, ~p"/invites/#{encoded_token}")
      assert html =~ "Welcome, New Hire"

      assert {:error, {:live_redirect, %{to: "/login"}}} =
               view
               |> form("form", user: %{password: "hello world!"})
               |> render_submit()

      assert %{hashed_password: hashed} = Accounts.get_user!(organization.id, invited.id)
      assert is_binary(hashed)
    end

    test "a reused token shows a safe error and redirects to /login", %{conn: conn} do
      %{encoded_token: encoded_token} = invite_fixture("reused@example.com")

      {:ok, view, _html} = live(conn, ~p"/invites/#{encoded_token}")

      assert {:error, {:live_redirect, %{to: "/login"}}} =
               view
               |> form("form", user: %{password: "hello world!"})
               |> render_submit()

      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/invites/#{encoded_token}")
    end

    test "an expired token shows a safe error and redirects to /login", %{conn: conn} do
      %{invited: invited, encoded_token: encoded_token} = invite_fixture("expired@example.com")

      invited
      |> UserToken.by_user_and_context_query("invite")
      |> Repo.update_all(set: [inserted_at: DateTime.add(DateTime.utc_now(), -8, :day)])

      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/invites/#{encoded_token}")
    end

    test "an invalid token shows a safe error and redirects to /login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/invites/bogus-token")
    end
  end
end
