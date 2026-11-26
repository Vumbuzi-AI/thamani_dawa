defmodule ThamaniDawaWeb.Api.V1.ManufacturerPalletController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Manufacturing.PalletLine
  alias ThamaniDawaWeb.Api.FallbackController
  alias ThamaniDawaWeb.Api.Response

  action_fallback FallbackController

  def current(conn, _params) do
    {:ok, pallet} = PalletLine.current(org_id(conn))
    Response.data(conn, pallet)
  end

  def open(conn, _params) do
    case PalletLine.open(org_id(conn)) do
      {:ok, pallet} -> Response.data(conn, pallet)
      {:error, reason} -> {:error, reason}
    end
  end

  def show(conn, %{"id" => id}) do
    case PalletLine.get(org_id(conn), id) do
      {:ok, pallet} -> Response.data(conn, pallet)
      {:error, reason} -> {:error, reason}
    end
  end

  def scan(conn, %{"id" => id} = params) do
    case PalletLine.scan(org_id(conn), id, params["raw"]) do
      {:ok, pallet} -> Response.data(conn, pallet)
      {:error, reason} -> {:error, reason}
    end
  end

  def mint(conn, %{"id" => id} = params) do
    case PalletLine.mint(org_id(conn), id, params["order_number"]) do
      {:ok, pallet} -> Response.data(conn, pallet)
      {:error, reason} -> {:error, reason}
    end
  end

  def verify(conn, %{"id" => id} = params) do
    case PalletLine.verify(org_id(conn), id, params["raw"]) do
      {:ok, pallet} -> Response.data(conn, pallet)
      {:error, reason} -> {:error, reason}
    end
  end

  defp org_id(conn), do: conn.assigns.current_mobile_user.organization_id
end
