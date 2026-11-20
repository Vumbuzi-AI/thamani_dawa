defmodule ThamaniDawaWeb.ErrorHTMLTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    html = render_to_string(ThamaniDawaWeb.ErrorHTML, "404", "html", [])
    assert html =~ "404"
    assert html =~ "This page is not here"
    assert html =~ "Back to home"
  end

  test "renders 403.html" do
    html = render_to_string(ThamaniDawaWeb.ErrorHTML, "403", "html", [])
    assert html =~ "You cannot open this page"
  end

  test "renders 500.html" do
    html = render_to_string(ThamaniDawaWeb.ErrorHTML, "500", "html", [])
    assert html =~ "Something went wrong"
    refute html =~ "Internal Server Error"
  end

  test "other HTML errors use the same page" do
    html = render_to_string(ThamaniDawaWeb.ErrorHTML, "400", "html", [])
    assert html =~ "400"
    assert html =~ "Bad Request"
    assert html =~ "Back to home"
  end

  test "an unknown address renders the not found page", %{conn: conn} do
    conn = get(conn, "/this-page-does-not-exist")
    html = html_response(conn, 404)

    assert html =~ "This page is not here"
    assert html =~ "Back to home"
    assert html =~ ~s(href="/")
  end
end
