defmodule ThamaniDawaWeb.Api.V1.ManufacturerSessionController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Distributor.MobileAuth
  alias ThamaniDawa.Distributor.MobileUser
  alias ThamaniDawa.Repo
  alias ThamaniDawaWeb.Api.FallbackController
  alias ThamaniDawaWeb.Api.Response
  alias ThamaniDawaWeb.Plugs.ManufacturerApiAuth

  action_fallback FallbackController

  def login(conn, params) do
    with {:ok, device_id} <- ManufacturerApiAuth.device_id(conn) do
      meta = %{device_id: device_id, ip: ManufacturerApiAuth.client_ip(conn)}

      case MobileAuth.login(params["username"], params["pin"], meta) do
        {:ok, tokens} ->
          user = Repo.preload(tokens.mobile_user, [:organization, :site])

          case ManufacturerApiAuth.manufacturer_packer(user) do
            :ok ->
              json(conn, session_body(%{tokens | mobile_user: user}))

            {:error, :account_inactive} ->
              MobileAuth.logout(tokens.access_token)
              {:error, :account_inactive}
          end

        {:error, :locked} ->
          {:error, {:account_locked, locked_until(params["username"])}}

        {:error, :inactive} ->
          {:error, :account_inactive}

        {:error, :invalid_credentials} ->
          Response.error(conn, 401, "invalid_credentials", "Invalid username or PIN.")

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def refresh(conn, params) do
    with {:ok, _device_id} <- ManufacturerApiAuth.device_id(conn) do
      case MobileAuth.refresh(params["refresh_token"]) do
        {:ok, tokens} ->
          user = Repo.preload(tokens.mobile_user, [:organization, :site])

          case ManufacturerApiAuth.manufacturer_packer(user) do
            :ok -> json(conn, session_body(%{tokens | mobile_user: user}))
            {:error, :account_inactive} -> {:error, :account_inactive}
          end

        {:error, :inactive} ->
          {:error, :account_inactive}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def logout(conn, _params) do
    _ = conn |> ManufacturerApiAuth.bearer() |> MobileAuth.logout()
    send_resp(conn, 204, "")
  end

  defp session_body(tokens) do
    user = tokens.mobile_user
    organization = user.organization
    expires_in = DateTime.diff(tokens.access_expires_at, DateTime.utc_now(), :second)

    %{
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
      expires_in: max(expires_in, 0),
      user: %{
        id: to_string(user.id),
        name: user.name,
        username: user.username,
        organization_name: organization && organization.name
      }
    }
  end

  defp locked_until(username) when is_binary(username) do
    case Repo.get_by(MobileUser, username: MobileUser.normalize_username(username)) do
      %MobileUser{locked_until: locked_until} -> locked_until
      _ -> nil
    end
  end

  defp locked_until(_username), do: nil
end
