defmodule ThamaniDawaWeb.Plugs.RequireIdempotency do
  @moduledoc false

  import Plug.Conn

  alias ThamaniDawaWeb.Api.Response

  def init(opts), do: opts

  def call(conn, _opts) do
    case idempotency_key(conn) do
      key when is_binary(key) and byte_size(key) > 0 and byte_size(key) <= 200 ->
        conn

      _ ->
        conn
        |> Response.error(400, "idempotency_key_required", "Send an Idempotency-Key header.")
        |> halt()
    end
  end

  def idempotency_key(conn) do
    case get_req_header(conn, "idempotency-key") do
      [key | _] -> String.trim(key)
      _ -> nil
    end
  end
end
