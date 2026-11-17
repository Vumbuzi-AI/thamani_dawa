defmodule ThamaniDawaWeb.Api.V1.RequisitionController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Requisitions
  alias ThamaniDawaWeb.Api.FallbackController
  alias ThamaniDawaWeb.Api.Params
  alias ThamaniDawaWeb.Api.Response
  alias ThamaniDawaWeb.Api.Serializer
  alias ThamaniDawaWeb.Api.V1.Helpers
  alias ThamaniDawaWeb.Plugs.RequireIdempotency
  alias ThamaniDawaWeb.Plugs.RequirePortal
  alias ThamaniDawaWeb.Plugs.RequireSite

  import Helpers

  action_fallback FallbackController

  plug RequirePortal, :pharmacy when action in [:index, :show, :create]
  plug RequirePortal, :org when action in [:queue, :queue_show, :review, :reject, :fulfill]
  plug RequireSite when action in [:index, :show, :create]
  plug RequireIdempotency when action in [:create, :review, :reject, :fulfill]

  def index(conn, params) do
    {page, per_page} = Params.page(params)

    requisitions = Requisitions.list_requisitions_for_site(org_id(conn), site_id(conn))
    {entries, meta} = Params.slice(requisitions, page, per_page)
    Response.page(conn, Enum.map(entries, &Serializer.requisition/1), meta)
  end

  def show(conn, %{"id" => id}) do
    with {:ok, requisition} <- load(conn, id),
         true <- requisition.site_id == site_id(conn) do
      Response.data(conn, Serializer.requisition(requisition))
    else
      false -> {:error, :not_found}
      other -> other
    end
  end

  def create(conn, params) do
    idempotent(conn, fn ->
      attrs =
        params
        |> Params.drop_tenant()
        |> Map.put("site_id", site_id(conn))

      case Requisitions.create_multi_requisition(org_id(conn), actor_id(conn), attrs) do
        {:ok, requisition} ->
          reload_created(conn, requisition)

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  def queue(conn, params) do
    {page, per_page} = Params.page(params)
    requisitions = Requisitions.list_requisitions(org_id(conn))
    {entries, meta} = Params.slice(requisitions, page, per_page)
    Response.page(conn, Enum.map(entries, &Serializer.requisition/1), meta)
  end

  def queue_show(conn, %{"id" => id}) do
    with {:ok, requisition} <- load(conn, id) do
      Response.data(conn, Serializer.requisition(requisition))
    end
  end

  def review(conn, %{"id" => id} = params) do
    idempotent(conn, fn ->
      with {:ok, id} <- parse_id(id),
           decisions when is_map(decisions) <- params["decisions"],
           {:ok, _requisition} <-
             Requisitions.review_lines(org_id(conn), id, actor_id(conn), decisions),
           {:ok, requisition} <- load(conn, id) do
        {:ok, 200, %{data: Serializer.requisition(requisition)}}
      else
        nil -> {:error, :bad_request}
        other -> other
      end
    end)
  end

  def reject(conn, %{"id" => id} = params) do
    idempotent(conn, fn ->
      with {:ok, id} <- parse_id(id),
           reason when is_binary(reason) and reason != "" <- params["rejection_reason"],
           {:ok, _requisition} <-
             Requisitions.reject_requisition(org_id(conn), id, actor_id(conn), reason),
           {:ok, requisition} <- load(conn, id) do
        {:ok, 200, %{data: Serializer.requisition(requisition)}}
      else
        false -> {:error, :bad_request}
        nil -> {:error, :bad_request}
        other -> other
      end
    end)
  end

  def fulfill(conn, %{"id" => _id} = params) do
    idempotent(conn, fn ->
      with {:ok, dispatches} <- dispatches(conn, params["dispatches"]),
           {:ok, _} <-
             Requisitions.fulfill_requisition_lines(org_id(conn), dispatches, actor_id(conn)),
           {:ok, requisition} <- load(conn, params["id"]) do
        {:ok, 200, %{data: Serializer.requisition(requisition)}}
      end
    end)
  end

  defp load(conn, id) do
    with {:ok, id} <- parse_id(id) do
      fetch(fn -> Requisitions.get_requisition!(org_id(conn), id) end)
    end
  end

  defp dispatches(_conn, rows) when not is_list(rows), do: {:error, :bad_request}

  defp dispatches(conn, rows) do
    rows
    |> Enum.reduce_while({:ok, []}, fn row, {:ok, acc} ->
      dispatch_row(conn, row, acc)
    end)
    |> unwrap_dispatches()
  end

  defp reload_created(conn, requisition) do
    {:ok, requisition} =
      fetch(fn -> Requisitions.get_requisition!(org_id(conn), requisition.id) end)

    {:ok, 201, %{data: Serializer.requisition(requisition)}}
  end

  defp dispatch_row(conn, row, acc) do
    with {:ok, line_id} <- Params.integer(row["line_id"]),
         {:ok, batch_id} <- Params.integer(row["batch_id"]),
         {:ok, quantity} <- Params.integer(row["quantity"]),
         {:ok, batch} <- load_batch(conn, batch_id) do
      {:cont, {:ok, [{line_id, batch, quantity} | acc]}}
    else
      :error -> {:halt, {:error, :bad_request}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp load_batch(conn, id) do
    fetch(fn -> Batches.get_batch!(org_id(conn), id) end)
  end

  defp unwrap_dispatches({:ok, list}), do: {:ok, Enum.reverse(list)}
  defp unwrap_dispatches(error), do: error
end
