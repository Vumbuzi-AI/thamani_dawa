defmodule ThamaniDawaWeb.Api.V1.Helpers do
  @moduledoc false

  import Plug.Conn, only: [put_status: 2]
  import Phoenix.Controller, only: [json: 2]

  alias ThamaniDawa.ApiIdempotency
  alias ThamaniDawa.Repo
  alias ThamaniDawaWeb.Api.Params
  alias ThamaniDawaWeb.Plugs.RequireIdempotency

  def scope(conn), do: conn.assigns.current_scope
  def org_id(conn), do: scope(conn).organization_id
  def site_id(conn), do: scope(conn).current_site_id
  def actor_id(conn), do: scope(conn).user.id

  def fetch(fun) when is_function(fun, 0) do
    {:ok, fun.()}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  def parse_id(id) do
    case Params.integer(id) do
      {:ok, parsed} -> {:ok, parsed}
      :error -> {:error, :not_found}
    end
  end

  def preload(record, preloads), do: Repo.preload(record, preloads)

  def idempotent(conn, fun) when is_function(fun, 0) do
    case ApiIdempotency.execute(
           actor_id(conn),
           RequireIdempotency.idempotency_key(conn),
           conn.params,
           fun
         ) do
      {:ok, status, body} -> conn |> put_status(status) |> json(body)
      {:error, reason} -> {:error, reason}
    end
  end
end
