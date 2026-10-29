defmodule ThamaniDawaWeb.AcceptInviteLiveTest do
  @moduledoc """
  Covers the acceptance criteria for completing the invite/accept flow (§7):
  a valid token lets a new hire set a password and is invalidated
  immediately after; a reused, expired, or otherwise invalid token fails
  safely (flash + redirect to /login), never a crash.
  """

  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
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
    test "a valid token lets the invited user set a six-character password", %{conn: conn} do
      %{organization: organization, invited: invited, encoded_token: encoded_token} =
        invite_fixture("valid@example.com")

      {:ok, view, html} = live(conn, ~p"/invites/#{encoded_token}")
      assert html =~ "Welcome, New Hire"
      assert has_element?(view, "#accept-invite-form")

      assert has_element?(
               view,
               "input[name='user[accepted_legal_terms]'][type='checkbox'][required]"
             )

      assert has_element?(view, "a[href='/terms'][target='_blank']", "Terms of Service")
      assert has_element?(view, "a[href='/privacy'][target='_blank']", "Privacy Policy")

      assert {:error, {:live_redirect, %{to: "/login"}}} =
               view
               |> form("#accept-invite-form",
                 user: %{password: "secret", accepted_legal_terms: "true"}
               )
               |> render_submit()

      assert %{
               hashed_password: hashed,
               legal_terms_accepted_at: accepted_at,
               legal_policy_version: "2026-10-29"
             } = Accounts.get_user!(organization.id, invited.id)

      assert is_binary(hashed)
      assert %DateTime{} = accepted_at
    end

    test "a reused token shows a safe error and redirects to /login", %{conn: conn} do
      %{encoded_token: encoded_token} = invite_fixture("reused@example.com")

      {:ok, view, _html} = live(conn, ~p"/invites/#{encoded_token}")

      assert {:error, {:live_redirect, %{to: "/login"}}} =
               view
               |> form("#accept-invite-form",
                 user: %{password: "hello world!", accepted_legal_terms: "true"}
               )
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

    test "a too-short password shows a validation error and does not activate the account", %{
      conn: conn
    } do
      %{organization: organization, invited: invited, encoded_token: encoded_token} =
        invite_fixture("short-password@example.com")

      {:ok, view, _html} = live(conn, ~p"/invites/#{encoded_token}")

      html =
        view
        |> form("#accept-invite-form",
          user: %{password: "short", accepted_legal_terms: "true"}
        )
        |> render_submit()

      assert html =~ "Must be at least 6 characters"

      assert %{hashed_password: nil} = Accounts.get_user!(organization.id, invited.id)
    end

    test "legal acknowledgement is required before the account is activated", %{conn: conn} do
      %{organization: organization, invited: invited, encoded_token: encoded_token} =
        invite_fixture("legal-acknowledgement@example.com")

      {:ok, view, _html} = live(conn, ~p"/invites/#{encoded_token}")

      html =
        view
        |> form("#accept-invite-form",
          user: %{password: "secret", accepted_legal_terms: "false"}
        )
        |> render_submit()

      assert has_element?(view, "#accept-invite-form")
      assert html =~ "You must accept the Terms of Service and Privacy Policy"

      assert %{hashed_password: nil, legal_terms_accepted_at: nil} =
               Accounts.get_user!(organization.id, invited.id)
    end

    test "activation ends an existing inviter session and renders the login form", %{conn: conn} do
      admin = user_fixture()

      {:ok, invited, encoded_token} =
        Accounts.invite_user(admin.organization_id, admin.id, %{
          name: "Session Handoff",
          email: "session-handoff@example.com",
          role: :pharmacist
        })

      authenticated_conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(authenticated_conn, ~p"/invites/#{encoded_token}")

      {:ok, login_conn} =
        view
        |> form("#accept-invite-form",
          user: %{password: "secret", accepted_legal_terms: "true"}
        )
        |> render_submit()
        |> follow_redirect(authenticated_conn, ~p"/login")

      assert html_response(login_conn, 200) =~
               "Password set — log in with your new account below."

      assert html_response(login_conn, 200) =~ "Welcome back"
      assert get_session(login_conn, :user_token) == nil
      assert Accounts.get_user!(admin.organization_id, invited.id).hashed_password
    end
  end
end
