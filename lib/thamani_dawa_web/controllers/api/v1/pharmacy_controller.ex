defmodule ThamaniDawaWeb.Api.V1.PharmacyController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Api.Scans
  alias ThamaniDawa.Batches
  alias ThamaniDawa.Dashboards
  alias ThamaniDawa.Payments
  alias ThamaniDawa.Prescriptions
  alias ThamaniDawa.Products
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

  plug RequirePortal, :pharmacy
  plug RequireSite
  plug RequireIdempotency when action in [:create_sale, :confirm_receipt]

  def dashboard(conn, _params) do
    org = org_id(conn)
    site = site_id(conn)

    Response.data(conn, %{
      stats: Serializer.stats(Dashboards.pharmacy_stats(org, site)),
      dispensed_today: Dashboards.dispensed_today(org, site),
      dispensed_by_day: Serializer.series(Dashboards.dispensed_by_day(org, site)),
      top_products: Serializer.series(Dashboards.top_dispensed_products(org, site))
    })
  end

  def scan(conn, params) do
    case Scans.lookup(org_id(conn), site_id(conn), params["raw"]) do
      {:ok, result} -> Response.data(conn, Serializer.scan(result))
      {:error, reason} -> {:error, reason}
    end
  end

  def stock(conn, params) do
    {page, per_page} = Params.page(params)

    result =
      Products.list_products_with_site_batches_paginated(org_id(conn), [site_id(conn)], page,
        page_size: per_page,
        search: params["search"]
      )

    Response.page(conn, Enum.map(result.entries, &Serializer.product/1), Params.scrivener(result))
  end

  def stock_product(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         {:ok, product} <- fetch(fn -> Products.get_product!(org_id(conn), id) end) do
      batches = Batches.list_batches_for_product(org_id(conn), product.id, [site_id(conn)])

      Response.data(conn, %{
        product: Serializer.product(product),
        batches: Enum.map(batches, &Serializer.batch/1)
      })
    end
  end

  def stock_batch(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         {:ok, batch} <- fetch(fn -> Batches.get_batch!(org_id(conn), id) end),
         true <- batch.site_id == site_id(conn) do
      Response.data(conn, Serializer.batch(batch, label: true))
    else
      false -> {:error, :not_found}
      other -> other
    end
  end

  def catalog(conn, params) do
    limit =
      params["limit"]
      |> then(fn
        nil ->
          25

        value ->
          case Params.integer(value) do
            {:ok, n} -> n |> max(1) |> min(100)
            :error -> 25
          end
      end)

    products =
      Products.quick_sale_products_for_site(
        org_id(conn),
        site_id(conn),
        params["search"] || "",
        params["category"],
        limit
      )

    Response.data(conn, %{
      products: Enum.map(products, &Serializer.product/1),
      categories: Products.quick_sale_categories_for_site(org_id(conn), site_id(conn))
    })
  end

  def create_sale(conn, params) do
    idempotent(conn, fn ->
      attrs = %{
        "payment_type" => params["payment_type"],
        "provider_reference" => params["provider_reference"],
        "patient_id" => params["patient_id"],
        "items" => sale_items(params["items"])
      }

      case Prescriptions.create_quick_sale(org_id(conn), site_id(conn), actor_id(conn), attrs) do
        {:ok, prescription} ->
          prescription = preload(prescription, :items)
          {:ok, 201, %{data: Serializer.prescription(prescription)}}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  def receipts(conn, _params) do
    batches = Batches.list_pending_batches_for_site(org_id(conn), site_id(conn))
    Response.data(conn, Enum.map(batches, &Serializer.batch/1))
  end

  def confirm_receipt(conn, %{"id" => id} = params) do
    idempotent(conn, fn ->
      with {:ok, id} <- parse_id(id),
           {:ok, batch} <- load_batch(conn, id),
           true <- batch.site_id == site_id(conn),
           {:ok, received} <-
             Batches.receive_batch(batch, actor_id(conn), Params.drop_tenant(params)) do
        {:ok, 200, %{data: Serializer.batch(received)}}
      else
        false -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  def transactions(conn, params) do
    {page, per_page} = Params.page(params)
    site = site_id(conn)

    payments =
      conn
      |> org_id()
      |> Payments.list_transactions()
      |> Enum.filter(&(&1.site_id == site))

    {entries, meta} = Params.slice(payments, page, per_page)

    Response.data(conn, %{
      transactions: Enum.map(entries, &Serializer.payment/1),
      meta: meta,
      by_payment_method: Serializer.series(Payments.sales_by_payment_method(org_id(conn), site))
    })
  end

  defp load_batch(conn, id) do
    fetch(fn -> Batches.get_batch!(org_id(conn), id) end)
  end

  defp sale_items(items) when is_list(items) do
    Enum.map(items, fn item ->
      %{
        "product_id" => item["product_id"],
        "quantity_prescribed" => item["quantity"] || item["quantity_prescribed"],
        "scanned_gtin" => item["scanned_gtin"],
        "scanned_barcode" => item["raw"]
      }
    end)
  end

  defp sale_items(_items), do: []
end
