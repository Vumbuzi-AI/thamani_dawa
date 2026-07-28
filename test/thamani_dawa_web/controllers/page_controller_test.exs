defmodule ThamaniDawaWeb.PageControllerTest do
  use ThamaniDawaWeb.ConnCase

  import ThamaniDawa.AccountsFixtures

  test "GET / unauthenticated shows Get started and Log in", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ "The pharmacy OS"
    assert html =~ "Log in"
    assert html =~ "Get started"
  end

  test "GET / authenticated as pharmacist links Dashboard to /pharmacy and shows avatar circle",
       %{
         conn: conn
       } do
    user = staff_fixture(%{name: "Alice Specialist", role: :pharmacist})

    conn =
      conn
      |> log_in_user(user)
      |> get(~p"/")

    html = html_response(conn, 200)
    assert html =~ "href=\"/pharmacy\""
    assert html =~ "A"
    assert html =~ "rounded-full"
    assert html =~ "aspect-square"
  end

  test "GET / authenticated as pharma_lab staff links Dashboard to /pharmacy", %{conn: conn} do
    user = staff_fixture(%{name: "Bob Dual", role: :pharma_lab})

    conn =
      conn
      |> log_in_user(user)
      |> get(~p"/")

    html = html_response(conn, 200)
    assert html =~ "href=\"/pharmacy\""
  end

  test "GET / authenticated as admin links Dashboard to /org/dashboard", %{conn: conn} do
    admin = user_fixture(%{name: "Charlie Admin"})

    conn =
      conn
      |> log_in_user(admin)
      |> get(~p"/")

    html = html_response(conn, 200)
    assert html =~ "href=\"/org/dashboard\""
  end

  test "GET /privacy", %{conn: conn} do
    conn = get(conn, ~p"/privacy")
    assert html_response(conn, 200) =~ "Privacy"
  end

  test "GET /terms", %{conn: conn} do
    conn = get(conn, ~p"/terms")
    assert html_response(conn, 200) =~ "Terms"
  end

  test "GET /contact", %{conn: conn} do
    conn = get(conn, ~p"/contact")
    html = html_response(conn, 200)
    assert html =~ "Contact"
    assert html =~ "<form"
  end
end
