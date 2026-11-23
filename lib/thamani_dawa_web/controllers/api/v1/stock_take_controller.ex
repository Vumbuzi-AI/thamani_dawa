defmodule ThamaniDawaWeb.Api.V1.StockTakeController do
  @moduledoc """
  Stock takes for the mobile app, on top of `ThamaniDawa.StockTakes`.

  Site staff count stock at their current site under `/pharmacy/stock-takes`
  (medicine) or `/lab/stock-takes` (lab consumables); the router passes the
  stock type in `conn.assigns.inventory_type`. Only admins approve or
  reject, under `/org/stock-takes`, matching the web queue.
  """

  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Batches
  alias ThamaniDawa.StockTakes
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

  @site_actions [:index, :create, :show, :add_item, :count, :submit, :reopen]
  @queue_actions [:queue, :queue_show, :approve, :reject]

  plug :require_portal
  plug RequireSite when action in @site_actions

  plug RequireIdempotency
       when action in [:create, :add_item, :count, :submit, :reopen, :approve, :reject]

  def index(conn, params) do
    {page, per_page} = Params.page(params)

    stock_takes =
      StockTakes.list_stock_takes_for_site(org_id(conn), site_id(conn), inventory_type(conn))

    stock_takes = StockTakes.filter_by_tab(stock_takes, params["status"])

    {entries, meta} = Params.slice(stock_takes, page, per_page)
    Response.page(conn, Enum.map(entries, &Serializer.stock_take/1), meta)
  end

  def create(conn, params) do
    idempotent(conn, fn ->
      attrs = %{
        "site_id" => site_id(conn),
        "inventory_type" => inventory_type(conn),
        "requested_by_id" => actor_id(conn),
        "notes" => params["notes"]
      }

      with {:ok, stock_take} <- StockTakes.create_stock_take(org_id(conn), attrs) do
        {:ok, 201, %{data: detail(conn, stock_take.id)}}
      end
    end)
  end

  def show(conn, %{"id" => id}) do
    with {:ok, stock_take} <- load_site_stock_take(conn, id) do
      Response.data(conn, detail(conn, stock_take))
    end
  end

  def add_item(conn, %{"id" => id} = params) do
    idempotent(conn, fn ->
      with {:ok, stock_take} <- load_site_stock_take(conn, id),
           {:ok, batch_id} <- integer_param(params["batch_id"]),
           {:ok, batch} <- load_site_batch(conn, batch_id, stock_take.site_id),
           {:ok, _item} <- StockTakes.add_item(stock_take, batch) do
        {:ok, 201, %{data: detail(conn, stock_take.id)}}
      end
    end)
  end

  def count(conn, %{"id" => id, "item_id" => item_id} = params) do
    idempotent(conn, fn ->
      with {:ok, stock_take} <- load_site_stock_take(conn, id),
           {:ok, item_id} <- parse_id(item_id),
           {:ok, item} <- find_item(stock_take, item_id),
           {:ok, counted} <- integer_param(params["counted_quantity"]),
           {:ok, _item} <-
             StockTakes.record_count(item, counted, actor_id(conn), notes(params)) do
        {:ok, 200, %{data: detail(conn, stock_take.id)}}
      end
    end)
  end

  def submit(conn, %{"id" => id}) do
    idempotent(conn, fn ->
      with {:ok, stock_take} <- load_site_stock_take(conn, id),
           {:ok, _submitted} <-
             StockTakes.submit_stock_take(org_id(conn), stock_take.id, actor_id(conn)) do
        {:ok, 200, %{data: detail(conn, stock_take.id)}}
      end
    end)
  end

  def reopen(conn, %{"id" => id}) do
    idempotent(conn, fn ->
      with {:ok, stock_take} <- load_site_stock_take(conn, id),
           {:ok, _reopened} <-
             StockTakes.reopen_stock_take(org_id(conn), stock_take.id, actor_id(conn)) do
        {:ok, 200, %{data: detail(conn, stock_take.id)}}
      end
    end)
  end

  def queue(conn, params) do
    {page, per_page} = Params.page(params)
    all = StockTakes.list_stock_takes(org_id(conn))

    {entries, meta} =
      Params.slice(StockTakes.filter_by_tab(all, params["status"]), page, per_page)

    conn
    |> json(%{
      data: Enum.map(entries, &Serializer.stock_take/1),
      meta: Map.put(meta, :tab_counts, StockTakes.tab_counts(all))
    })
  end

  def queue_show(conn, %{"id" => id}) do
    with {:ok, stock_take} <- load_stock_take(conn, id) do
      Response.data(conn, Serializer.stock_take(stock_take))
    end
  end

  def approve(conn, %{"id" => id}) do
    idempotent(conn, fn ->
      with {:ok, stock_take} <- load_stock_take(conn, id),
           {:ok, _approved} <-
             StockTakes.approve_stock_take(org_id(conn), stock_take.id, actor_id(conn)),
           {:ok, approved} <- load_stock_take(conn, stock_take.id) do
        {:ok, 200, %{data: Serializer.stock_take(approved)}}
      end
    end)
  end

  def reject(conn, %{"id" => id} = params) do
    idempotent(conn, fn ->
      with {:ok, stock_take} <- load_stock_take(conn, id),
           {:ok, _rejected} <-
             StockTakes.reject_stock_take(
               org_id(conn),
               stock_take.id,
               actor_id(conn),
               params["rejection_reason"]
             ),
           {:ok, rejected} <- load_stock_take(conn, stock_take.id) do
        {:ok, 200, %{data: Serializer.stock_take(rejected)}}
      end
    end)
  end

  defp require_portal(conn, _opts) do
    portal =
      cond do
        action_name(conn) in @queue_actions -> :org
        inventory_type(conn) == :lab_consumable -> :lab
        true -> :pharmacy
      end

    RequirePortal.call(conn, portal)
  end

  defp inventory_type(conn), do: Map.get(conn.assigns, :inventory_type, :medicine)

  # The stock take plus the batches that can still be added to it, so the
  # app can offer them without a second request.
  defp detail(conn, %{} = stock_take) do
    already_added = MapSet.new(stock_take.items, & &1.batch_id)

    addable =
      if stock_take.status == :draft do
        conn
        |> org_id()
        |> Batches.list_active_batches_for_site_by_inventory_type(
          stock_take.site_id,
          stock_take.inventory_type
        )
        |> Enum.reject(&MapSet.member?(already_added, &1.id))
        |> Enum.map(&Serializer.batch/1)
      else
        []
      end

    stock_take |> Serializer.stock_take() |> Map.put(:addable_batches, addable)
  end

  defp detail(conn, id) when is_integer(id) do
    detail(conn, StockTakes.get_stock_take!(org_id(conn), id))
  end

  defp load_stock_take(conn, id) do
    with {:ok, id} <- parse_id(id) do
      fetch(fn -> StockTakes.get_stock_take!(org_id(conn), id) end)
    end
  end

  # Site staff only see stock takes at their current site and of the stock
  # type for this portal; anything else is reported as not found.
  defp load_site_stock_take(conn, id) do
    with {:ok, stock_take} <- load_stock_take(conn, id) do
      if stock_take.site_id == site_id(conn) and
           stock_take.inventory_type == inventory_type(conn) do
        {:ok, stock_take}
      else
        {:error, :not_found}
      end
    end
  end

  defp load_site_batch(conn, batch_id, site_id) do
    fetch(fn -> Batches.get_batch_for_site!(org_id(conn), batch_id, site_id) end)
  end

  defp find_item(stock_take, item_id) do
    case Enum.find(stock_take.items, &(&1.id == item_id)) do
      nil -> {:error, :not_found}
      item -> {:ok, item}
    end
  end

  defp integer_param(value) do
    case Params.integer(value) do
      {:ok, parsed} -> {:ok, parsed}
      :error -> {:error, :bad_request}
    end
  end

  defp notes(%{"notes" => notes}) when is_binary(notes), do: %{"notes" => notes}
  defp notes(_params), do: %{}
end
