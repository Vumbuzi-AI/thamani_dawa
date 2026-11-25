defmodule ThamaniDawaWeb.Api.V1.CatalogController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Suppliers
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

  plug RequireIdempotency
       when action in [
              :create_product,
              :update_product,
              :create_batch,
              :dispatch,
              :create_supplier,
              :update_supplier,
              :create_site,
              :update_site
            ]

  def products(conn, params) do
    {page, per_page} = Params.page(params)

    result =
      Products.list_products_paginated(org_id(conn), page,
        page_size: per_page,
        search: params["search"],
        category: params["category"]
      )

    Response.page(conn, Enum.map(result.entries, &Serializer.product/1), Params.scrivener(result))
  end

  # `undispatched` is org warehouse stock not yet dispatched to a site (as on
  # the web product page). `pending_receipt` lists site batches dispatched
  # but not yet confirmed by the site.
  def show_product(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         {:ok, product} <- fetch(fn -> Products.get_product!(org_id(conn), id) end) do
      batches = Batches.list_batches_for_product(org_id(conn), product.id)
      undispatched = Batches.list_undispatched_batches_for_product(org_id(conn), product.id)

      Response.data(conn, %{
        product: Serializer.product(product),
        batches: Enum.map(batches, &Serializer.batch/1),
        undispatched: Enum.map(undispatched, &Serializer.batch/1),
        pending_receipt:
          batches
          |> Enum.filter(&is_nil(&1.received_at))
          |> Enum.map(&Serializer.batch/1)
      })
    end
  end

  def create_product(conn, params) do
    idempotent(conn, fn ->
      case Products.create_product(org_id(conn), Params.drop_tenant(params)) do
        {:ok, product} -> {:ok, 201, %{data: Serializer.product(product)}}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  def update_product(conn, %{"id" => id} = params) do
    idempotent(conn, fn ->
      with {:ok, id} <- parse_id(id),
           {:ok, product} <- load_product(conn, id),
           {:ok, product} <- Products.update_product(product, Params.drop_tenant(params)) do
        {:ok, 200, %{data: Serializer.product(product)}}
      end
    end)
  end

  # Mirrors the web "add batch" flow. With a `site_id` the batch is received
  # straight into that site, auto-approved, and the EPCIS facility receipt is
  # recorded (`receive_directly_at_site/4`). Without one, a single-site
  # organization receives into its only site the same way, and a multi-site
  # organization records org warehouse stock to dispatch later.
  def create_batch(conn, %{"product_id" => product_id} = params) do
    idempotent(conn, fn ->
      attrs =
        params
        |> Params.drop_tenant()
        |> Map.put("product_id", product_id)

      with {:ok, destination} <- batch_destination(conn, attrs["site_id"]),
           {:ok, batch} <- receive_batch(conn, destination, attrs) do
        {:ok, 201, %{data: Serializer.batch(batch, label: true)}}
      end
    end)
  end

  def show_batch(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         {:ok, batch} <- fetch(fn -> Batches.get_batch!(org_id(conn), id) end) do
      Response.data(conn, Serializer.batch(batch, label: true))
    end
  end

  # Dispatches org warehouse stock to a site, where it waits for the site to
  # confirm receipt. Site batches cannot be moved again (`already_dispatched`).
  def dispatch(conn, %{"id" => id} = params) do
    idempotent(conn, fn ->
      with {:ok, id} <- parse_id(id),
           {:ok, batch} <- load_batch(conn, id),
           {:ok, site_id} <- required_integer(params["site_id"], :site_id_required),
           {:ok, quantity} <- required_integer(params["quantity"], :quantity_required),
           {:ok, _site} <- load_site(conn, site_id),
           {:ok, dispatched} <- Batches.dispatch_to_site(batch, site_id, quantity) do
        {:ok, 201, %{data: Serializer.batch(dispatched)}}
      end
    end)
  end

  def suppliers(conn, params) do
    {page, per_page} = Params.page(params)
    suppliers = Suppliers.list_suppliers(org_id(conn))
    {entries, meta} = Params.slice(suppliers, page, per_page)
    Response.page(conn, Enum.map(entries, &Serializer.supplier/1), meta)
  end

  def create_supplier(conn, params) do
    idempotent(conn, fn ->
      case Suppliers.create_supplier(org_id(conn), Params.drop_tenant(params)) do
        {:ok, supplier} -> {:ok, 201, %{data: Serializer.supplier(supplier)}}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  def update_supplier(conn, %{"id" => id} = params) do
    idempotent(conn, fn ->
      with {:ok, id} <- parse_id(id),
           {:ok, supplier} <- load_supplier(conn, id),
           {:ok, supplier} <- Suppliers.update_supplier(supplier, Params.drop_tenant(params)) do
        {:ok, 200, %{data: Serializer.supplier(supplier)}}
      end
    end)
  end

  def sites(conn, params) do
    {page, per_page} = Params.page(params)
    sites = Sites.list_sites(org_id(conn))
    {entries, meta} = Params.slice(sites, page, per_page)
    Response.page(conn, Enum.map(entries, &Serializer.site/1), meta)
  end

  def show_site(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         {:ok, site} <- fetch(fn -> Sites.get_site!(org_id(conn), id) end) do
      Response.data(conn, Serializer.site(site))
    end
  end

  def create_site(conn, params) do
    idempotent(conn, fn ->
      case Sites.create_site(org_id(conn), Params.drop_tenant(params)) do
        {:ok, site} -> {:ok, 201, %{data: Serializer.site(site)}}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  def update_site(conn, %{"id" => id} = params) do
    idempotent(conn, fn ->
      with {:ok, id} <- parse_id(id),
           {:ok, site} <- load_site(conn, id),
           {:ok, site} <- Sites.update_site(site, Params.drop_tenant(params)) do
        {:ok, 200, %{data: Serializer.site(site)}}
      end
    end)
  end

  defp batch_destination(conn, value) when value in [nil, ""] do
    case Sites.list_sites(org_id(conn)) do
      [site] -> {:ok, {:site, site.id}}
      _sites -> {:ok, :warehouse}
    end
  end

  defp batch_destination(_conn, value) do
    with {:ok, site_id} <- required_integer(value, :site_id_required),
         do: {:ok, {:site, site_id}}
  end

  defp receive_batch(conn, {:site, site_id}, attrs) do
    Batches.receive_directly_at_site(org_id(conn), site_id, actor_id(conn), attrs)
  end

  defp receive_batch(conn, :warehouse, attrs) do
    Batches.receive_into_org_stock(org_id(conn), Map.delete(attrs, "site_id"))
  end

  defp required_integer(value, missing) when value in [nil, ""], do: {:error, missing}

  defp required_integer(value, missing) do
    case Params.integer(value) do
      {:ok, parsed} -> {:ok, parsed}
      :error -> {:error, invalid_reason(missing)}
    end
  end

  defp invalid_reason(:site_id_required), do: :invalid_site_id
  defp invalid_reason(:quantity_required), do: :invalid_quantity

  defp load_product(conn, id) do
    fetch(fn -> Products.get_product!(org_id(conn), id) end)
  end

  defp load_batch(conn, id) do
    fetch(fn -> Batches.get_batch!(org_id(conn), id) end)
  end

  defp load_supplier(conn, id) do
    fetch(fn -> Suppliers.get_supplier!(org_id(conn), id) end)
  end

  defp load_site(conn, id) do
    fetch(fn -> Sites.get_site!(org_id(conn), id) end)
  end
end
