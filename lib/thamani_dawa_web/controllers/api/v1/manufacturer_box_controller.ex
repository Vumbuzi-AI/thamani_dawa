defmodule ThamaniDawaWeb.Api.V1.ManufacturerBoxController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Manufacturing.Mobile
  alias ThamaniDawaWeb.Api.FallbackController
  alias ThamaniDawaWeb.Api.Response

  action_fallback FallbackController

  def show(conn, %{"id" => id}) do
    case Mobile.get_box(org_id(conn), id, mobile_user(conn)) do
      {:ok, box} -> Response.data(conn, box)
      {:error, reason} -> {:error, reason}
    end
  end

  def scan(conn, %{"id" => id} = params) do
    case Mobile.claim_scan(org_id(conn), id, params["raw"], mobile_user(conn)) do
      {:ok, :repeat, scan} -> Response.data(conn, scan)
      {:ok, :created, scan} -> Response.data(conn, scan, 201)
      {:error, reason} -> {:error, reason}
    end
  end

  def delete_scan(conn, %{"id" => id, "serial" => serial}) do
    case Mobile.release_scan(org_id(conn), id, serial, mobile_user(conn)) do
      :ok -> send_resp(conn, 204, "")
      {:error, reason} -> {:error, reason}
    end
  end

  def save(conn, %{"id" => id}) do
    key =
      case get_req_header(conn, "idempotency-key") do
        [value] -> value
        _ -> ""
      end

    case Mobile.save_box(org_id(conn), id, key, mobile_user(conn)) do
      {:ok, box} -> Response.data(conn, box)
      {:error, reason} -> {:error, reason}
    end
  end

  defp mobile_user(conn), do: conn.assigns.current_mobile_user
  defp org_id(conn), do: mobile_user(conn).organization_id
end
