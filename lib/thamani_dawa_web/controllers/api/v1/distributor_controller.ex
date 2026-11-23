defmodule ThamaniDawaWeb.Api.V1.DistributorController do
  @moduledoc """
  Distributor portal endpoints for signed-in distributor staff (email and
  password, like the other portals): goods receipts and their receiving
  discrepancies, customers, and customer returns.

  Access follows the web's distributor portal (`Portals.portal_access?/2`):
  a distributor or admin in an organization on the distributor model. Like
  the web, staff stationed at a warehouse only see that warehouse's receipts
  and returns, and new returns are put away there.

  Packing shipments is done by mobile users; see
  `ThamaniDawaWeb.Api.V1.DistributorMobileController`.
  """

  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.CustomerReturns
  alias ThamaniDawa.Customers
  alias ThamaniDawa.GoodsReceipts
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawaWeb.Api.FallbackController
  alias ThamaniDawaWeb.Api.Params
  alias ThamaniDawaWeb.Api.Response
  alias ThamaniDawaWeb.Api.Serializer
  alias ThamaniDawaWeb.Api.V1.Helpers
  alias ThamaniDawaWeb.Plugs.RequireIdempotency
  alias ThamaniDawaWeb.Plugs.RequirePortal

  import Helpers

  action_fallback FallbackController

  plug RequirePortal, :distributor

  plug RequireIdempotency
       when action in [
              :resolve_discrepancy,
              :create_customer,
              :update_customer,
              :create_return,
              :add_return_item,
              :remove_return_item,
              :receive_return,
              :set_item_condition,
              :inspect_return,
              :complete_return
            ]

  # Goods receipts

  def receipts(conn, params) do
    {page, per_page} = Params.page(params)

    receipts =
      conn
      |> org_id()
      |> GoodsReceipts.list_receipts()
      |> Enum.filter(&receipt_at_site?(&1, site_id(conn)))

    {entries, meta} = Params.slice(receipts, page, per_page)
    Response.page(conn, Enum.map(entries, &Serializer.goods_receipt/1), meta)
  end

  def receipt(conn, %{"id" => id}) do
    with {:ok, receipt} <- load_receipt(conn, id) do
      Response.data(conn, Serializer.goods_receipt(receipt))
    end
  end

  def discrepancies(conn, params) do
    {page, per_page} = Params.page(params)

    discrepancies =
      conn
      |> org_id()
      |> GoodsReceipts.list_open_discrepancies()
      |> Enum.filter(&at_site?(&1.site_id, site_id(conn)))

    {entries, meta} = Params.slice(discrepancies, page, per_page)
    Response.page(conn, Enum.map(entries, &Serializer.discrepancy/1), meta)
  end

  # Close an open discrepancy as found, lost or stolen. Lost and stolen need
  # a resolution_reference and fire the matching EPCIS event.
  def resolve_discrepancy(conn, %{"id" => id} = params) do
    idempotent(conn, fn ->
      with {:ok, discrepancy} <- load_discrepancy(conn, id),
           :ok <- open(discrepancy),
           {:ok, resolved} <-
             GoodsReceipts.resolve_discrepancy(
               discrepancy,
               actor_id(conn),
               Map.take(params, ["status", "resolution_reference"])
             ) do
        {:ok, 200, %{data: Serializer.discrepancy(resolved)}}
      end
    end)
  end

  # Customers

  def customers(conn, params) do
    {page, per_page} = Params.page(params)
    customers = Customers.list_customers(org_id(conn))
    {entries, meta} = Params.slice(customers, page, per_page)
    Response.page(conn, Enum.map(entries, &Serializer.customer/1), meta)
  end

  def create_customer(conn, params) do
    idempotent(conn, fn ->
      with {:ok, customer} <- Customers.create_customer(org_id(conn), customer_attrs(params)) do
        {:ok, 201, %{data: Serializer.customer(customer)}}
      end
    end)
  end

  def update_customer(conn, %{"id" => id} = params) do
    idempotent(conn, fn ->
      with {:ok, customer} <- load_customer(conn, id),
           {:ok, updated} <- Customers.update_customer(customer, customer_attrs(params)) do
        {:ok, 200, %{data: Serializer.customer(updated)}}
      end
    end)
  end

  # Customer returns: draft -> received -> inspected -> completed.

  def returns(conn, params) do
    {page, per_page} = Params.page(params)

    returns =
      conn
      |> org_id()
      |> CustomerReturns.list_returns()
      |> Enum.filter(&at_site?(&1.site_id, site_id(conn)))
      |> filter_status(params["status"])

    {entries, meta} = Params.slice(returns, page, per_page)
    Response.page(conn, Enum.map(entries, &Serializer.customer_return/1), meta)
  end

  def show_return(conn, %{"id" => id}) do
    with {:ok, customer_return} <- load_return(conn, id) do
      Response.data(conn, Serializer.customer_return(customer_return))
    end
  end

  def create_return(conn, params) do
    idempotent(conn, fn ->
      with {:ok, customer} <- load_customer(conn, params["customer_id"]),
           {:ok, site} <- return_site(conn, params["site_id"]),
           attrs = %{
             "customer_id" => customer.id,
             "site_id" => site.id,
             "reason" => params["reason"],
             "notes" => params["notes"],
             "document_reference" => params["document_reference"]
           },
           {:ok, customer_return} <- CustomerReturns.create_return(org_id(conn), attrs) do
        {:ok, 201, %{data: return_body(conn, customer_return.id)}}
      end
    end)
  end

  # Adds a pack by hand. Returns opened from a shipment on the web only take
  # that shipment's packs, so they are refused here.
  def add_return_item(conn, %{"id" => id} = params) do
    idempotent(conn, fn ->
      with {:ok, customer_return} <- load_return(conn, id),
           :ok <- not_from_shipment(customer_return),
           {:ok, product} <- load_product(conn, params["product_id"]),
           attrs = %{
             "product_id" => product.id,
             "quantity" => params["quantity"],
             "batch_no" => params["batch_no"],
             "expiry_date" => params["expiry_date"],
             "serial" => params["serial"],
             "matched" => false
           },
           {:ok, _item} <- CustomerReturns.add_item(customer_return, attrs) do
        {:ok, 201, %{data: return_body(conn, customer_return.id)}}
      end
    end)
  end

  def remove_return_item(conn, %{"id" => id, "item_id" => item_id}) do
    idempotent(conn, fn ->
      with {:ok, customer_return} <- load_return(conn, id),
           {:ok, item} <- find_item(customer_return, item_id),
           {:ok, _item} <- CustomerReturns.remove_item(item) do
        {:ok, 200, %{data: return_body(conn, customer_return.id)}}
      end
    end)
  end

  def receive_return(conn, %{"id" => id}) do
    idempotent(conn, fn ->
      with {:ok, customer_return} <- load_return(conn, id),
           {:ok, _received} <- CustomerReturns.mark_received(customer_return, actor_id(conn)) do
        {:ok, 200, %{data: return_body(conn, customer_return.id)}}
      end
    end)
  end

  # The inspector's call on one item: sellable, damaged or quarantine.
  def set_item_condition(conn, %{"id" => id, "item_id" => item_id} = params) do
    idempotent(conn, fn ->
      with {:ok, customer_return} <- load_return(conn, id),
           :ok <- status(customer_return, :received),
           {:ok, item} <- find_item(customer_return, item_id),
           {:ok, _item} <- CustomerReturns.set_item_condition(item, params["condition"]) do
        {:ok, 200, %{data: return_body(conn, customer_return.id)}}
      end
    end)
  end

  def inspect_return(conn, %{"id" => id}) do
    idempotent(conn, fn ->
      with {:ok, customer_return} <- load_return(conn, id),
           {:ok, _inspected} <- CustomerReturns.mark_inspected(customer_return) do
        {:ok, 200, %{data: return_body(conn, customer_return.id)}}
      end
    end)
  end

  # Puts the stock away as new batches and fires the EPCIS receiving event.
  def complete_return(conn, %{"id" => id}) do
    idempotent(conn, fn ->
      with {:ok, customer_return} <- load_return(conn, id),
           :ok <- status(customer_return, :inspected),
           {:ok, _completed} <-
             CustomerReturns.complete_return(org_id(conn), customer_return.id, actor_id(conn)) do
        {:ok, 200, %{data: return_body(conn, customer_return.id)}}
      end
    end)
  end

  defp customer_attrs(params) do
    Map.take(params, [
      "name",
      "gln",
      "address",
      "customer_type",
      "contact_name",
      "contact_email",
      "contact_phone"
    ])
  end

  defp return_body(conn, id) do
    conn |> org_id() |> CustomerReturns.get_return!(id) |> Serializer.customer_return()
  end

  # Staff stationed at a warehouse work at that warehouse only; without a
  # station they can pick any of the organization's distribution sites.
  defp return_site(conn, raw_site_id) do
    case site_id(conn) do
      nil -> requested_site(conn, raw_site_id)
      station_id -> fetch(fn -> Sites.get_site!(org_id(conn), station_id) end)
    end
  end

  defp requested_site(_conn, nil), do: {:error, :site_id_required}

  defp requested_site(conn, raw_site_id) do
    with {:ok, id} <- invalid_site(Params.integer(raw_site_id)),
         {:ok, site} <- fetch(fn -> Sites.get_site!(org_id(conn), id) end) do
      if Site.distribution?(site), do: {:ok, site}, else: {:error, :invalid_site_id}
    end
  end

  defp invalid_site({:ok, id}), do: {:ok, id}
  defp invalid_site(:error), do: {:error, :invalid_site_id}

  defp load_receipt(conn, id) do
    with {:ok, id} <- parse_id(id),
         {:ok, receipt} <- fetch(fn -> GoodsReceipts.get_receipt!(org_id(conn), id) end) do
      if receipt_at_site?(receipt, site_id(conn)), do: {:ok, receipt}, else: {:error, :not_found}
    end
  end

  defp load_discrepancy(conn, id) do
    with {:ok, id} <- parse_id(id),
         {:ok, discrepancy} <-
           fetch(fn -> GoodsReceipts.get_discrepancy!(org_id(conn), id) end) do
      if at_site?(discrepancy.site_id, site_id(conn)),
        do: {:ok, discrepancy},
        else: {:error, :not_found}
    end
  end

  defp load_customer(conn, id) do
    with {:ok, id} <- parse_id(id) do
      fetch(fn -> Customers.get_customer!(org_id(conn), id) end)
    end
  end

  defp load_product(conn, id) do
    with {:ok, id} <- parse_id(id) do
      fetch(fn -> Products.get_product!(org_id(conn), id) end)
    end
  end

  defp load_return(conn, id) do
    with {:ok, id} <- parse_id(id),
         {:ok, customer_return} <- fetch(fn -> CustomerReturns.get_return!(org_id(conn), id) end) do
      if at_site?(customer_return.site_id, site_id(conn)),
        do: {:ok, customer_return},
        else: {:error, :not_found}
    end
  end

  defp find_item(customer_return, raw_item_id) do
    with {:ok, item_id} <- parse_id(raw_item_id) do
      case Enum.find(customer_return.items, &(&1.id == item_id)) do
        nil -> {:error, :not_found}
        item -> {:ok, item}
      end
    end
  end

  defp receipt_at_site?(_receipt, nil), do: true

  defp receipt_at_site?(receipt, site_id) do
    Enum.any?(receipt.items, &(&1.site_id == site_id)) or
      Enum.any?(receipt.discrepancies, &(&1.site_id == site_id))
  end

  defp at_site?(_record_site_id, nil), do: true
  defp at_site?(record_site_id, site_id), do: record_site_id == site_id

  defp filter_status(returns, status)
       when status in ["draft", "received", "inspected", "completed"],
       do: Enum.filter(returns, &(Atom.to_string(&1.status) == status))

  defp filter_status(returns, _status), do: returns

  defp open(%{status: :open}), do: :ok
  defp open(_discrepancy), do: {:error, :already_resolved}

  defp not_from_shipment(%{shipment_id: nil}), do: :ok
  defp not_from_shipment(_customer_return), do: {:error, :shipment_return}

  defp status(%{status: status}, status), do: :ok
  defp status(_customer_return, :received), do: {:error, :not_received}
  defp status(_customer_return, :inspected), do: {:error, :not_inspected}
end
