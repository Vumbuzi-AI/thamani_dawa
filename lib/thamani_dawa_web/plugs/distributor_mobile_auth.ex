defmodule ThamaniDawaWeb.Plugs.DistributorMobileAuth do
  @moduledoc """
  Loads `conn.assigns.mobile_user` from `Authorization: Bearer` for the
  distributor packing app. These tokens come from username + PIN sign-in
  (`ThamaniDawa.Distributor.MobileAuth`), not from `/api/v1/login`, so the
  two token kinds never open each other's routes.

  No audit actor is set: audit rows reference `users`, and a mobile user is
  not one. Shipment events already record the mobile user.
  """

  import Plug.Conn

  alias ThamaniDawa.Distributor.MobileAuth
  alias ThamaniDawaWeb.Api.Response
  alias ThamaniDawaWeb.Plugs.ApiAuth

  def init(opts), do: opts

  def call(conn, _opts) do
    case MobileAuth.authenticate(ApiAuth.bearer(conn)) do
      {:ok, mobile_user} ->
        assign(conn, :mobile_user, mobile_user)

      {:error, _reason} ->
        conn
        |> Response.error(401, "unauthorized", "Sign in again.")
        |> halt()
    end
  end
end
