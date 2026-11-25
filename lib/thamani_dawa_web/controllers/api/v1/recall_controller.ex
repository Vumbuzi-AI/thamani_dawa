defmodule ThamaniDawaWeb.Api.V1.RecallController do
  @moduledoc """
  Recalls as seen by one organization: the recalled batches it holds, and
  acknowledging that it has been reached. Admin only (`/org` portal), as
  `ThamaniDawa.Recalls.acknowledge_holder/2` expects an org admin.
  """

  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Recalls
  alias ThamaniDawa.Repo
  alias ThamaniDawaWeb.Api.FallbackController
  alias ThamaniDawaWeb.Api.Params
  alias ThamaniDawaWeb.Api.Response
  alias ThamaniDawaWeb.Api.Serializer
  alias ThamaniDawaWeb.Api.V1.Helpers
  alias ThamaniDawaWeb.Plugs.RequireIdempotency
  alias ThamaniDawaWeb.Plugs.RequirePortal

  import Helpers

  action_fallback FallbackController

  plug RequirePortal, :org
  plug RequireIdempotency when action in [:acknowledge]

  def index(conn, params) do
    {page, per_page} = Params.page(params)
    holders = Recalls.list_holders_for_organization(org_id(conn), status(params["status"]))
    {entries, meta} = Params.slice(holders, page, per_page)
    Response.page(conn, Enum.map(entries, &Serializer.recall_holder/1), meta)
  end

  def acknowledge(conn, %{"id" => id}) do
    idempotent(conn, fn ->
      with {:ok, id} <- parse_id(id),
           {:ok, holder} <- acknowledge_holder(id, scope(conn).user) do
        holder = Repo.preload(holder, [:recall, :batch])
        {:ok, 200, %{data: Serializer.recall_holder(holder)}}
      end
    end)
  end

  # `acknowledge_holder/2` raises for an unknown id; report that as not found.
  defp acknowledge_holder(id, user) do
    with {:ok, result} <- fetch(fn -> Recalls.acknowledge_holder(id, user) end), do: result
  end

  defp status("open"), do: :open
  defp status("closed"), do: :closed
  defp status(_status), do: nil
end
