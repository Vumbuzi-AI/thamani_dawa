defmodule ThamaniDawaWeb.Plugs.Cors do
  @moduledoc """
  Lets the Expo web origin call `/api`. Native apps do not send Origin.
  OPTIONS is answered here so it never 404s on a missing route.
  """

  import Plug.Conn

  @methods "GET, POST, PUT, PATCH, DELETE, OPTIONS"
  @headers "Accept, Authorization, Content-Type, Idempotency-Key, X-Device-Id"

  def init(opts), do: opts

  def call(%Plug.Conn{request_path: path} = conn, _opts) do
    if String.starts_with?(path, "/api") do
      cors(conn)
    else
      conn
    end
  end

  defp cors(conn) do
    origin = origin(conn)

    conn =
      conn
      |> put_resp_header("vary", "origin")
      |> maybe_allow_origin(origin)
      |> put_resp_header("access-control-allow-methods", @methods)
      |> put_resp_header("access-control-allow-headers", @headers)
      |> put_resp_header("access-control-max-age", "86400")

    if conn.method == "OPTIONS" do
      conn |> send_resp(204, "") |> halt()
    else
      conn
    end
  end

  defp origin(conn) do
    case get_req_header(conn, "origin") do
      [value] -> value
      _ -> nil
    end
  end

  defp maybe_allow_origin(conn, origin) when is_binary(origin) do
    if allowed_origin?(origin) do
      put_resp_header(conn, "access-control-allow-origin", origin)
    else
      conn
    end
  end

  defp maybe_allow_origin(conn, _), do: conn

  defp allowed_origin?(origin) do
    case URI.parse(origin) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        host in ["localhost", "127.0.0.1"]

      _ ->
        false
    end
  end
end
