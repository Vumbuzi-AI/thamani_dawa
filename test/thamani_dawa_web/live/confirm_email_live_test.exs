defmodule ThamaniDawaWeb.ConfirmEmailLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import ThamaniDawa.AccountsFixtures

  alias ThamaniDawa.Accounts

  describe "the :require_confirmed_email gate" do
    test "redirects an unconfirmed admin away from /onboarding to /confirm-email", %{conn: conn} do
      admin = user_fixture(%{confirmed: false})

      assert {:error, {:redirect, %{to: "/confirm-email"}}} =
               live(log_in_user(conn, admin), ~p"/onboarding")
    end

    test "lets a confirmed admin through to /onboarding", %{conn: conn} do
      admin = user_fixture()

      assert {:ok, _view, _html} = live(log_in_user(conn, admin), ~p"/onboarding")
    end
  end

  describe "mount" do
    test "shows the waiting page with the admin's email", %{conn: conn} do
      admin = user_fixture(%{confirmed: false, email: "pending.admin@example.com"})

      {:ok, view, html} = live(log_in_user(conn, admin), ~p"/confirm-email")

      assert html =~ "Confirm your email"
      assert html =~ "pending.admin@example.com"
      assert has_element?(view, "#confirm-email-resend", "Resend confirmation email")
    end
  end

  describe "resend" do
    test "sends another confirmation email and starts a cooldown", %{conn: conn} do
      admin = user_fixture(%{confirmed: false})

      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/confirm-email")

      view |> element("#confirm-email-resend") |> render_click()

      assert_email_sent(fn email ->
        assert email.subject == "Confirm your Thamani Dawa account"
      end)

      assert render(view) =~ "Confirmation email resent to #{admin.email}"
      refute has_element?(view, "#confirm-email-resend:not([disabled])")
      assert has_element?(view, "#confirm-email-resend[disabled]")
    end

    test "does not resend again before the cooldown elapses", %{conn: conn} do
      admin = user_fixture(%{confirmed: false})

      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/confirm-email")

      view |> element("#confirm-email-resend") |> render_click()
      assert_email_sent(fn _email -> true end)

      render_click(view, "resend", %{})

      refute_received {:email, _}
    end

    test "updates the visible countdown on each timer tick", %{conn: conn} do
      admin = user_fixture(%{confirmed: false})

      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/confirm-email")

      view |> element("#confirm-email-resend") |> render_click()
      assert_email_sent(fn _email -> true end)
      assert has_element?(view, "#confirm-email-resend", "Resend in 30s")

      send(view.pid, :tick)

      assert has_element?(view, "#confirm-email-resend", "Resend in 29s")
    end

    test "replacing the confirm token lets the newest link still confirm the account", %{
      conn: conn
    } do
      admin = user_fixture(%{confirmed: false})

      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/confirm-email")

      view |> element("#confirm-email-resend") |> render_click()

      assert_email_sent(fn email ->
        [_, token] = Regex.run(~r{/confirm/([^"<\s]+)}, email.text_body)
        send(self(), {:latest_token, token})
      end)

      assert_receive {:latest_token, token}
      assert {:ok, confirmed} = Accounts.confirm_user(token)
      assert confirmed.id == admin.id
    end
  end
end
