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

  # `undispatched` was removed on 20 Nov 2026: every batch is now bound to a
  # site from receipt, so there is no org-level pool left to dispatch from.
  # `pending_receipt` replaces it — batches transferred to a site that the
  # site has not confirmed yet (the only stock not yet on a shelf).
  def show_product(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         {:ok, product} <- fetch(fn -> Products.get_product!(org_id(conn), id) end) do
      batches = Batches.list_batches_for_product(org_id(conn), product.id)

      Response.data(conn, %{
        product: Serializer.product(product),
        batches: Enum.map(batches, &Serializer.batch/1),
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

  # API batches are received straight into a site and auto-approved, the same
  # as the web receive flow: `receive_directly_at_site/4` stamps the receipt
  # and records the EPCIS facility receipt.
  def create_batch(conn, %{"product_id" => product_id} = params) do
    idempotent(conn, fn ->
      attrs =
        params
        |> Params.drop_tenant()
        |> Map.put("product_id", product_id)

      with {:ok, site_id} <- batch_site_id(attrs["site_id"]),
           {:ok, batch} <-
             Batches.receive_directly_at_site(org_id(conn), site_id, actor_id(conn), attrs) do
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

  # A site-to-site transfer: debits the source batch and creates a batch at
  # the destination site that waits for that site to confirm receipt.
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

  defp batch_site_id(value), do: required_integer(value, :site_id_required)

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
