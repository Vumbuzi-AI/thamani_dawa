defmodule ThamaniDawaWeb.Api.V1.ManufacturerBatchController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Manufacturing.Mobile
  alias ThamaniDawaWeb.Api.FallbackController
  alias ThamaniDawaWeb.Api.Response

  action_fallback FallbackController

  def index(conn, _params) do
    batches = Mobile.list_batches(org_id(conn), mobile_user(conn))
    Response.data(conn, batches)
  end

  def show(conn, %{"id" => id}) do
    case Mobile.get_batch(org_id(conn), id, mobile_user(conn)) do
      {:ok, batch} -> Response.data(conn, batch)
      {:error, reason} -> {:error, reason}
    end
  end

  def parties(conn, %{"id" => id} = params) do
    case Mobile.save_parties(
           org_id(conn),
           id,
           params["from_gln"],
           params["to_gln"],
           mobile_user(conn)
         ) do
      {:ok, batch} -> Response.data(conn, batch)
      {:error, reason} -> {:error, reason}
    end
  end

  def resolve(conn, %{"raw" => raw}) do
    case Mobile.resolve_line(org_id(conn), raw, mobile_user(conn)) do
      {:ok, payload} -> Response.data(conn, payload)
      {:error, reason} -> {:error, reason}
    end
  end

  def resolve(_conn, _params), do: {:error, :bad_request}

  def create_box(conn, %{"id" => id}) do
    case Mobile.open_box(org_id(conn), id, mobile_user(conn)) do
      {:ok, :existing, box} -> Response.data(conn, box)
      {:ok, :created, box} -> Response.data(conn, box, 201)
      {:error, reason} -> {:error, reason}
    end
  end

  defp mobile_user(conn), do: conn.assigns.current_mobile_user
  defp org_id(conn), do: mobile_user(conn).organization_id
end
