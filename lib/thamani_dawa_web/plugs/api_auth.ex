defmodule ThamaniDawaWeb.Plugs.ApiAuth do
  @moduledoc """
  Loads `current_scope` from `Authorization: Bearer`. The token is a mobile
  access token, never the browser session cookie.
  """

  import Plug.Conn

  alias ThamaniDawa.Accounts.MobileSession
  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Repo
  alias ThamaniDawaWeb.Api.Response

  def init(opts), do: opts

  def call(conn, _opts) do
    with token when is_binary(token) <- bearer(conn),
         {:ok, user} <- MobileSession.verify_access(token),
         true <- user.organization.is_active do
      Repo.put_audit_actor(user)
      assign(clear_actor_after_send(conn), :current_scope, Scope.for_user(user))
    else
      false ->
        unauthorized(conn, "account_inactive", "This account is disabled.", 403)

      _ ->
        unauthorized(conn, "unauthorized", "Sign in again.", 401)
    end
  end

  def bearer(conn) do
    case get_req_header(conn, "authorization") do
      [value] -> parse_bearer(value)
      _ -> nil
    end
  end

  defp clear_actor_after_send(conn) do
    register_before_send(conn, fn conn ->
      Repo.clear_audit_actor()
      conn
    end)
  end

  defp parse_bearer(value) do
    case String.split(value, " ", parts: 2) do
      [scheme, token] -> bearer_token(scheme, token)
      _ -> nil
    end
  end

  defp bearer_token(scheme, token) do
    if String.downcase(scheme) == "bearer", do: String.trim(token)
  end

  defp unauthorized(conn, code, message, status) do
    conn
    |> Response.error(status, code, message)
    |> halt()
  end
end
