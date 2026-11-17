defmodule ThamaniDawaWeb.Plugs.RequirePortal do
  @moduledoc false

  import Plug.Conn

  alias ThamaniDawaWeb.Api.Access
  alias ThamaniDawaWeb.Api.Response

  def init(portal) when portal in [:org, :pharmacy, :lab], do: portal

  def call(conn, portal) do
    if Access.portal?(conn.assigns.current_scope, portal) do
      conn
    else
      conn
      |> Response.error(403, "forbidden", "You cannot open this part of the app.")
      |> halt()
    end
  end
end
