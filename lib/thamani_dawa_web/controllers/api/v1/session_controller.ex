defmodule ThamaniDawaWeb.Api.V1.SessionController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Accounts.MobileSession
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Repo
  alias ThamaniDawaWeb.Api.FallbackController
  alias ThamaniDawaWeb.Api.Params
  alias ThamaniDawaWeb.Api.Response
  alias ThamaniDawaWeb.Api.Serializer
  alias ThamaniDawaWeb.Api.V1.Helpers
  alias ThamaniDawaWeb.Plugs.ApiAuth

  action_fallback FallbackController

  def login(conn, params) do
    case MobileSession.log_in(params["email"], params["password"]) do
      {:ok, tokens, user} -> json(conn, Serializer.session(tokens, user))
      {:error, reason} -> {:error, reason}
    end
  end

  def refresh(conn, params) do
    case MobileSession.refresh(params["refresh_token"]) do
      {:ok, tokens, user} -> json(conn, Serializer.session(tokens, user))
      {:error, reason} -> {:error, reason}
    end
  end

  def signup(conn, params) do
    org = params["organization"] || %{}
    user = Map.put(params["user"] || %{}, "accepted_legal_terms", truthy?(params["user"]))
    site = params["site"]

    result =
      if is_map(site) and site != %{} do
        Organizations.signup(org, site, user)
      else
        Organizations.signup(org, user)
      end

    case result do
      {:ok, %{user: created}} ->
        case MobileSession.log_in(created.email, user["password"]) do
          {:ok, tokens, signed_in} ->
            conn |> put_status(201) |> json(Serializer.session(tokens, signed_in))

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def accept_invite(conn, %{"token" => token} = params) do
    user = Accounts.get_user_by_invite_token(token)
    attrs = %{"password" => params["password"], "accepted_legal_terms" => true}

    if user do
      login_after_invite(conn, user, attrs, params["password"])
    else
      {:error, :invalid_token}
    end
  end

  def logout(conn, _params) do
    _ = conn |> ApiAuth.bearer() |> MobileSession.revoke_access()
    send_resp(conn, 204, "")
  end

  def me(conn, _params) do
    Response.data(conn, Serializer.user(Helpers.scope(conn).user))
  end

  def sites(conn, _params) do
    sites = Accounts.list_sites_for_user(Helpers.scope(conn))
    Response.data(conn, Enum.map(sites, &Serializer.site/1))
  end

  def switch_site(conn, params) do
    site_id =
      case params["site_id"] do
        blank when blank in [nil, ""] -> nil
        value -> Params.integer(value)
      end

    case site_id do
      :error ->
        {:error, :bad_request}

      parsed ->
        id = if is_tuple(parsed), do: elem(parsed, 1), else: parsed

        case Accounts.switch_current_site(Helpers.scope(conn), id) do
          {:ok, user} ->
            user = Repo.preload(user, [:organization, :current_site, :sites], force: true)
            Response.data(conn, Serializer.user(user))

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp login_after_invite(conn, user, attrs, password) do
    case Accounts.accept_invite(user, attrs) do
      {:ok, accepted} -> open_mobile_session(conn, accepted.email, password)
      {:error, reason} -> {:error, reason}
    end
  end

  defp open_mobile_session(conn, email, password) do
    case MobileSession.log_in(email, password) do
      {:ok, tokens, signed_in} -> json(conn, Serializer.session(tokens, signed_in))
      {:error, reason} -> {:error, reason}
    end
  end

  defp truthy?(%{"accepted_legal_terms" => value}) when value in [true, "true"], do: true
  defp truthy?(_user), do: false
end
