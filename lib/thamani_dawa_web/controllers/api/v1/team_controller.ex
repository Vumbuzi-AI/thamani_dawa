defmodule ThamaniDawaWeb.Api.V1.TeamController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Repo
  alias ThamaniDawaWeb.Api.FallbackController
  alias ThamaniDawaWeb.Api.Params
  alias ThamaniDawaWeb.Api.Response
  alias ThamaniDawaWeb.Api.Serializer
  alias ThamaniDawaWeb.Api.V1.Helpers
  alias ThamaniDawaWeb.Endpoint
  alias ThamaniDawaWeb.Plugs.RequireIdempotency
  alias ThamaniDawaWeb.Plugs.RequirePortal

  import Helpers

  action_fallback FallbackController

  plug RequirePortal, :org
  plug RequireIdempotency when action in [:create, :update]

  def index(conn, params) do
    {page, per_page} = Params.page(params)
    users = Accounts.list_users(org_id(conn))
    {entries, meta} = Params.slice(users, page, per_page)

    Response.page(
      conn,
      Enum.map(entries, fn user ->
        user = Repo.preload(user, [:organization, :current_site, :sites])
        Serializer.user(user)
      end),
      meta
    )
  end

  def create(conn, params) do
    idempotent(conn, fn ->
      case Accounts.invite_user(org_id(conn), actor_id(conn), Params.drop_tenant(params)) do
        {:ok, user, token} ->
          org = scope(conn).user.organization

          _ =
            Accounts.deliver_user_invite(
              user,
              org.name,
              scope(conn).user.name,
              token,
              &invite_url/1
            )

          user = Repo.preload(user, [:organization, :current_site, :sites])
          {:ok, 201, %{data: Serializer.user(user)}}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  def update(conn, %{"id" => id} = params) do
    idempotent(conn, fn ->
      with {:ok, id} <- parse_id(id) do
        update_member(conn, id, params)
      end
    end)
  end

  defp update_member(conn, id, params) do
    result = change_member(conn, id, params)

    case result do
      {:ok, user} ->
        user = Repo.preload(user, [:organization, :current_site, :sites], force: true)
        {:ok, 200, %{data: Serializer.user(user)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp change_member(conn, id, params) do
    if Map.has_key?(params, "is_active") do
      active? = params["is_active"] in [true, "true"]
      Accounts.set_user_active(org_id(conn), actor_id(conn), id, active?)
    else
      Accounts.update_user(org_id(conn), id, Params.drop_tenant(params))
    end
  end

  defp invite_url(token), do: Endpoint.url() <> "/invites/" <> token
end
