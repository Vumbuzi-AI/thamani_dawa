defmodule ThamaniDawaWeb.Api.V1.ManufacturerGlnController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Manufacturing.Mobile
  alias ThamaniDawaWeb.Api.Response

  def index(conn, params) do
    user = conn.assigns.current_mobile_user
    Response.data(conn, Mobile.search_glns(user.organization_id, params["q"]))
  end
end
