defmodule ThamaniDawaWeb.Api.V1.DisposalController do
  @moduledoc """
  Inventory disposals for the mobile app, on top of
  `ThamaniDawa.InventoryDisposals`: expiry write-offs (`kind: "expiry"`) and
  supplier returns (`kind: "returned"`).

  Site staff build and submit disposals at their current site under
  `/pharmacy/disposals` (medicine) or `/lab/disposals` (lab consumables);
  the router passes the stock type in `conn.assigns.inventory_type`. Only
  admins approve or reject, under `/org/disposals`, matching the web queue.
  """

  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Batches
  alias ThamaniDawa.InventoryDisposals
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

  @site_actions [:index, :create, :show, :add_item, :remove_item, :submit, :reopen]
  @queue_actions [:queue, :queue_show, :approve, :reject]

  plug :require_portal
  plug RequireSite when action in @site_actions

  plug RequireIdempotency
       when action in [:create, :add_item, :remove_item, :submit, :reopen, :approve, :reject]

  def index(conn, params) do
    {page, per_page} = Params.page(params)

    disposals =
      InventoryDisposals.list_disposals_for_site(
        org_id(conn),
        site_id(conn),
        kind(params["kind"]),
        inventory_type(conn)
      )

    disposals = InventoryDisposals.filter_by_tab(disposals, params["status"])

    {entries, meta} = Params.slice(disposals, page, per_page)
    Response.page(conn, Enum.map(entries, &Serializer.disposal/1), meta)
  end

  def create(conn, params) do
    idempotent(conn, fn ->
      attrs = %{
        "site_id" => site_id(conn),
        "kind" => params["kind"],
        "inventory_type" => inventory_type(conn),
        "requested_by_id" => actor_id(conn),
        "reason" => params["reason"],
        "notes" => params["notes"]
      }

      with {:ok, disposal} <- InventoryDisposals.create_disposal(org_id(conn), attrs) do
        {:ok, 201, %{data: detail(conn, disposal.id)}}
      end
    end)
  end

  def show(conn, %{"id" => id}) do
    with {:ok, disposal} <- load_site_disposal(conn, id) do
      Response.data(conn, detail(conn, disposal))
    end
  end

  def add_item(conn, %{"id" => id} = params) do
    idempotent(conn, fn ->
      with {:ok, disposal} <- load_site_disposal(conn, id),
           {:ok, batch_id} <- integer_param(params["batch_id"]),
           {:ok, quantity} <- integer_param(params["quantity"]),
           :ok <- positive(quantity),
           {:ok, batch} <- load_site_batch(conn, batch_id, disposal.site_id),
           {:ok, _item} <- InventoryDisposals.add_item(disposal, batch, quantity) do
        {:ok, 201, %{data: detail(conn, disposal.id)}}
      end
    end)
  end

  def remove_item(conn, %{"id" => id, "item_id" => item_id}) do
    idempotent(conn, fn ->
      with {:ok, disposal} <- load_site_disposal(conn, id),
           {:ok, item_id} <- parse_id(item_id),
           {:ok, item} <- find_item(disposal, item_id),
           {:ok, _removed} <- InventoryDisposals.remove_item(item) do
        {:ok, 200, %{data: detail(conn, disposal.id)}}
      end
    end)
  end

  def submit(conn, %{"id" => id}) do
    idempotent(conn, fn ->
      with {:ok, disposal} <- load_site_disposal(conn, id),
           {:ok, _submitted} <-
             InventoryDisposals.submit_disposal(org_id(conn), disposal.id, actor_id(conn)) do
        {:ok, 200, %{data: detail(conn, disposal.id)}}
      end
    end)
  end

  def reopen(conn, %{"id" => id}) do
    idempotent(conn, fn ->
      with {:ok, disposal} <- load_site_disposal(conn, id),
           {:ok, _reopened} <-
             InventoryDisposals.reopen_disposal(org_id(conn), disposal.id, actor_id(conn)) do
        {:ok, 200, %{data: detail(conn, disposal.id)}}
      end
    end)
  end

  def queue(conn, params) do
    {page, per_page} = Params.page(params)

    all = filter_kind(InventoryDisposals.list_disposals(org_id(conn)), params["kind"])

    {entries, meta} =
      Params.slice(InventoryDisposals.filter_by_tab(all, params["status"]), page, per_page)

    json(conn, %{
      data: Enum.map(entries, &Serializer.disposal/1),
      meta: Map.put(meta, :tab_counts, InventoryDisposals.tab_counts(all))
    })
  end

  def queue_show(conn, %{"id" => id}) do
    with {:ok, disposal} <- load_disposal(conn, id) do
      Response.data(conn, Serializer.disposal(disposal))
    end
  end

  def approve(conn, %{"id" => id}) do
    idempotent(conn, fn ->
      with {:ok, disposal} <- load_disposal(conn, id),
           {:ok, _approved} <-
             InventoryDisposals.approve_disposal(org_id(conn), disposal.id, actor_id(conn)),
           {:ok, approved} <- load_disposal(conn, disposal.id) do
        {:ok, 200, %{data: Serializer.disposal(approved)}}
      end
    end)
  end

  def reject(conn, %{"id" => id} = params) do
    idempotent(conn, fn ->
      with {:ok, disposal} <- load_disposal(conn, id),
           {:ok, _rejected} <-
             InventoryDisposals.reject_disposal(
               org_id(conn),
               disposal.id,
               actor_id(conn),
               params["rejection_reason"]
             ),
           {:ok, rejected} <- load_disposal(conn, disposal.id) do
        {:ok, 200, %{data: Serializer.disposal(rejected)}}
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

  # The web lists default to expiry write-offs; supplier returns are the
  # other tab.
  defp kind("returned"), do: :returned
  defp kind(_kind), do: :expiry

  defp filter_kind(disposals, value) when value in ["expiry", "returned"] do
    wanted = kind(value)
    Enum.filter(disposals, &(&1.kind == wanted))
  end

  defp filter_kind(disposals, _value), do: disposals

  # The disposal plus the site's batches that can still be added to it.
  defp detail(conn, %{} = disposal) do
    already_added = MapSet.new(disposal.items, & &1.batch_id)

    addable =
      if disposal.status == :draft do
        conn
        |> org_id()
        |> Batches.list_active_batches_for_site_by_inventory_type(
          disposal.site_id,
          disposal.inventory_type
        )
        |> Enum.reject(&MapSet.member?(already_added, &1.id))
        |> Enum.map(&Serializer.batch/1)
      else
        []
      end

    disposal |> Serializer.disposal() |> Map.put(:addable_batches, addable)
  end

  defp detail(conn, id) when is_integer(id) do
    detail(conn, InventoryDisposals.get_disposal!(org_id(conn), id))
  end

  defp load_disposal(conn, id) do
    with {:ok, id} <- parse_id(id) do
      fetch(fn -> InventoryDisposals.get_disposal!(org_id(conn), id) end)
    end
  end

  defp load_site_disposal(conn, id) do
    with {:ok, disposal} <- load_disposal(conn, id) do
      if disposal.site_id == site_id(conn) and disposal.inventory_type == inventory_type(conn) do
        {:ok, disposal}
      else
        {:error, :not_found}
      end
    end
  end

  defp load_site_batch(conn, batch_id, site_id) do
    fetch(fn -> Batches.get_batch_for_site!(org_id(conn), batch_id, site_id) end)
  end

  defp find_item(disposal, item_id) do
    case Enum.find(disposal.items, &(&1.id == item_id)) do
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

  defp positive(quantity) when quantity > 0, do: :ok
  defp positive(_quantity), do: {:error, :invalid_dispatch_quantity}
end
