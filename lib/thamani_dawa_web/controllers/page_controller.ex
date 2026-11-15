defmodule ThamaniDawaWeb.PageController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawaWeb.PageComponents

  plug :put_layout, [html: {ThamaniDawaWeb.Layouts, :landing}] when action in [:home]
  plug :put_layout, [html: {ThamaniDawaWeb.Layouts, :contact}] when action in [:contact]

  def home(conn, _params) do
    case conn.assigns[:current_scope] do
      %{user: user} = scope when not is_nil(user) ->
        redirect(conn, to: PageComponents.dashboard_path(scope))

      _scope ->
        render(conn, :home)
    end
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
