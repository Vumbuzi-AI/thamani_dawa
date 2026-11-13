defmodule ThamaniDawaWeb.PageController do
  use ThamaniDawaWeb, :controller

  plug :put_layout, [html: {ThamaniDawaWeb.Layouts, :landing}] when action in [:home]

  def home(conn, _params) do
    render(conn, :home)
  end

  def privacy(conn, _params) do
    render(conn, :privacy)
  end

  def terms(conn, _params) do
    render(conn, :terms)
  end

  def contact(conn, _params) do
    render(conn, :contact, form: Phoenix.Component.to_form(%{}))
  end
end
