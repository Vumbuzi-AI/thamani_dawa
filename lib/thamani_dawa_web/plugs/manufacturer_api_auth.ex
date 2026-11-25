defmodule ThamaniDawaWeb.Plugs.ManufacturerApiAuth do
  @moduledoc """
  Loads the manufacturer packer from `Authorization: Bearer`. PIN sessions
  from `Distributor.MobileAuth`, not the staff email/password API.
  """

  import Plug.Conn

  alias ThamaniDawa.Distributor.MobileAuth
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawaWeb.Api.Response

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, _device_id} <- device_id(conn),
         token when is_binary(token) <- bearer(conn),
         {:ok, mobile_user} <- MobileAuth.authenticate(token),
         :ok <- manufacturer_packer(mobile_user) do
      assign(conn, :current_mobile_user, mobile_user)
    else
      {:error, :account_inactive} ->
        unauthorized(conn, "account_inactive", "This account is disabled.", 403)

      {:error, :device_required} ->
        unauthorized(conn, "bad_request", "Missing X-Device-Id.", 400)

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

  def device_id(conn) do
    case get_req_header(conn, "x-device-id") do
      [value] ->
        case String.trim(value) do
          "" -> {:error, :device_required}
          device_id -> {:ok, device_id}
        end

      _ ->
        {:error, :device_required}
    end
  end

  def manufacturer_packer(mobile_user) do
    organization = mobile_user.organization || %{}
    site = mobile_user.site

    cond do
      not match?(%Organization{}, organization) -> {:error, :account_inactive}
      not organization.is_active -> {:error, :account_inactive}
      not Organization.manufacturer?(organization) -> {:error, :account_inactive}
      not match?(%{active: true}, mobile_user) -> {:error, :account_inactive}
      not match?(%Site{}, site) -> {:error, :account_inactive}
      not Site.manufacturer?(site) -> {:error, :account_inactive}
      not site.is_active -> {:error, :account_inactive}
      true -> :ok
    end
  end

  def client_ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end

  defp parse_bearer(value) do
    case String.split(value, " ", parts: 2) do
      [scheme, token] ->
        if String.downcase(scheme) == "bearer", do: String.trim(token)

      _ ->
        nil
    end
  end

  defp unauthorized(conn, code, message, status) do
    conn
    |> Response.error(status, code, message)
    |> halt()
  end
end
