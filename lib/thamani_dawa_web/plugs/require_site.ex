defmodule ThamaniDawaWeb.Plugs.RequireSite do
  @moduledoc false

  import Plug.Conn

  alias ThamaniDawaWeb.Api.Response

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns.current_scope.current_site_id do
      conn
    else
      conn
      |> Response.error(422, "site_required", "Choose a site first.")
      |> halt()
    end
  end
end
