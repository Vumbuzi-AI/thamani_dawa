defmodule ThamaniDawaWeb.SessionControllerTest do
  @moduledoc """
  Covers the acceptance criteria for role-based login redirects (§7):
  admin lands on /org/sites, pharmacist lands on /pharmacy, lab technician lands on /lab.
  """

  use ThamaniDawaWeb.ConnCase, async: true

  import Ecto.Changeset
  import ThamaniDawa.AccountsFixtures

  alias ThamaniDawa.Repo

  describe "GET /login" do
    test "renders the login form", %{conn: conn} do
      conn = get(conn, ~p"/login")

      assert html_response(conn, 200) =~ "Welcome back"
    end
  end

  describe "DELETE /logout" do
    test "logs the user out and redirects home", %{conn: conn} do
      admin = user_fixture()

      conn =
        conn
        |> log_in_user(admin)
        |> delete(~p"/logout")

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_token) == nil
    end
  end

  describe "POST /login" do
    test "redirects an admin to /org/sites", %{conn: conn} do
      admin = user_fixture()

      conn =
        post(conn, ~p"/login", %{"email" => admin.email, "password" => valid_user_password()})

      assert redirected_to(conn) == ~p"/org/sites"
    end

    test "redirects a pharmacist to /pharmacy", %{conn: conn} do
      pharmacist = staff_fixture(%{role: :pharmacist})

      conn =
        post(conn, ~p"/login", %{
          "email" => pharmacist.email,
          "password" => valid_user_password()
        })

      assert redirected_to(conn) == ~p"/pharmacy"
    end

    test "redirects a lab technician to /lab", %{conn: conn} do
      lab_technician = staff_fixture(%{role: :lab_technician})

      conn =
        post(conn, ~p"/login", %{
          "email" => lab_technician.email,
          "password" => valid_user_password()
        })

      assert redirected_to(conn) == ~p"/lab"
    end

    test "redirects combined pharmacy/lab staff to /pharmacy", %{conn: conn} do
      pharma_lab = staff_fixture(%{role: :pharma_lab})

      conn =
        post(conn, ~p"/login", %{
          "email" => pharma_lab.email,
          "password" => valid_user_password()
        })

      assert redirected_to(conn) == ~p"/pharmacy"
    end

    test "shows an error and does not log in with an invalid password", %{conn: conn} do
      admin = user_fixture()

      conn = post(conn, ~p"/login", %{"email" => admin.email, "password" => "wrong password"})

      assert html_response(conn, 200) =~ "Invalid email or password"
    end

    test "shows the same generic error and does not log in a deactivated user", %{conn: conn} do
      admin = user_fixture()
      {:ok, deactivated} = admin |> change(is_active: false) |> Repo.update()

      conn =
        post(conn, ~p"/login", %{
          "email" => deactivated.email,
          "password" => valid_user_password()
        })

      assert html_response(conn, 200) =~ "Invalid email or password"
    end
  end
end
