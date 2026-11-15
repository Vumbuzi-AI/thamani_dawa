defmodule ThamaniDawaWeb.ConfirmationControllerTest do
  use ThamaniDawaWeb.ConnCase

  alias ThamaniDawa.Accounts

  import ThamaniDawa.AccountsFixtures

  describe "GET /confirm/:token" do
    test "confirms the user and redirects to login", %{conn: conn} do
      user = user_fixture(%{confirmed: false})

      {:ok, :ok} =
        Accounts.deliver_user_confirmation_instructions(user, fn token ->
          send(self(), {:token, token})
          "http://localhost:4000/confirm/#{token}"
        end)

      assert_receive {:token, encoded_token}

      conn = get(conn, ~p"/confirm/#{encoded_token}")

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Email confirmed"
      assert Accounts.get_user_by_email(user.email).confirmed_at
    end

    test "redirects to login with an error for an invalid token", %{conn: conn} do
      conn = get(conn, ~p"/confirm/bogus")

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or has expired"
    end
  end
end
