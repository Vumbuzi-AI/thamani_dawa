defmodule ThamaniDawaWeb.Api.V1.LabController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Api.Scans
  alias ThamaniDawa.Batches
  alias ThamaniDawa.Dashboards
  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.LabTests
  alias ThamaniDawa.Payments
  alias ThamaniDawaWeb.Api.Access
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

  plug RequirePortal, :lab
  plug RequireSite

  plug RequireIdempotency
       when action in [
              :create_order,
              :collect,
              :save_result,
              :consume,
              :pay,
              :receive_batch,
              :create_receipt,
              :create_test,
              :update_test
            ]

  def dashboard(conn, _params) do
    org = org_id(conn)
    site = site_id(conn)

    Response.data(conn, %{
      stats: Serializer.stats(Dashboards.lab_stats(org, site)),
      by_status:
        Enum.map(Dashboards.lab_orders_by_status(org, site), fn {status, count} ->
          %{status: Atom.to_string(status), count: count}
        end)
    })
  end

  def scan(conn, params) do
    case Scans.lookup(org_id(conn), site_id(conn), params["raw"]) do
      {:ok, result} -> Response.data(conn, Serializer.scan(result))
      {:error, reason} -> {:error, reason}
    end
  end

  def orders(conn, params) do
    {page, per_page} = Params.page(params)
    site = site_id(conn)

    orders =
      conn
      |> org_id()
      |> LabOrders.list_lab_orders_with_patient()
      |> Enum.filter(&(&1.site_id == site))

    {entries, meta} = Params.slice(orders, page, per_page)
    Response.page(conn, Enum.map(entries, &Serializer.lab_order/1), meta)
  end

  def show_order(conn, %{"id" => id}) do
    with {:ok, order} <- load_order(conn, id) do
      Response.data(conn, Serializer.lab_order(preload(order, :lab_order_results)))
    end
  end

  def create_order(conn, params) do
    idempotent(conn, fn ->
      case Params.integer(params["patient_id"]) do
        {:ok, patient_id} -> create_lab_order(conn, params, patient_id)
        :error -> {:error, :bad_request}
      end
    end)
  end

  def collect(conn, %{"id" => id} = params) do
    idempotent(conn, fn ->
      with {:ok, id} <- parse_id(id),
           {:ok, _order} <- load_order(conn, id),
           {:ok, result_ids} <- integers(params["result_ids"]),
           {:ok, specimen} <-
             LabOrders.collect_specimen(org_id(conn), id, result_ids, actor_id(conn), params) do
        {:ok, 201,
         %{
           data:
             Serializer.stats(
               Map.take(specimen, [:id, :specimen_type, :specimen_number, :status])
             )
         }}
      else
        :error -> {:error, :bad_request}
        other -> other
      end
    end)
  end

  def save_result(conn, %{"id" => id} = params) do
    idempotent(conn, fn ->
      with {:ok, id} <- parse_id(id),
           values when is_map(values) <- params["values"],
           {:ok, result} <-
             LabOrders.record_result(org_id(conn), id, actor_id(conn), values,
               reason: params["reason"]
             ) do
        {:ok, 200, %{data: Serializer.lab_result(result)}}
      else
        nil -> {:error, :bad_request}
        other -> other
      end
    end)
  end

  def consume(conn, %{"id" => order_id} = params) do
    idempotent(conn, fn ->
      with {:ok, order_id} <- parse_id(order_id),
           {:ok, _order} <- load_order(conn, order_id),
           {:ok, batch_id} <- Params.integer(params["batch_id"]),
           {:ok, quantity} <- Params.integer(params["quantity"]),
           {:ok, usage} <-
             LabOrders.record_consumable_usage(org_id(conn), batch_id, actor_id(conn), quantity,
               lab_order_id: order_id
             ) do
        {:ok, 201, %{data: %{id: usage.id, quantity: usage.quantity, batch_id: usage.batch_id}}}
      else
        :error -> {:error, :bad_request}
        other -> other
      end
    end)
  end

  def pay(conn, %{"id" => id} = params) do
    idempotent(conn, fn ->
      with {:ok, id} <- parse_id(id),
           {:ok, _order} <- load_order(conn, id),
           {:ok, payment} <-
             Payments.create_payment(org_id(conn), %{
               "lab_order_id" => id,
               "amount" => money(params["amount"]),
               "payment_type" => params["payment_type"],
               "provider_reference" => params["provider_reference"]
             }) do
        {:ok, 201, %{data: Serializer.payment(payment)}}
      else
        other -> other
      end
    end)
  end

  def stock(conn, params) do
    {page, per_page} = Params.page(params)

    batches =
      conn
      |> org_id()
      |> Batches.list_active_lab_consumable_batches_for_site(site_id(conn))
      |> Enum.filter(&Batches.usable?/1)

    {entries, meta} = Params.slice(batches, page, per_page)
    Response.page(conn, Enum.map(entries, &Serializer.batch/1), meta)
  end

  def receipts(conn, _params) do
    batches = Batches.list_pending_batches_for_site(org_id(conn), site_id(conn))
    Response.data(conn, Enum.map(batches, &Serializer.batch/1))
  end

  def create_receipt(conn, params) do
    idempotent(conn, fn ->
      attrs = params |> Params.drop_tenant() |> Map.put("site_id", site_id(conn))

      case Batches.receive_directly_at_site(org_id(conn), site_id(conn), actor_id(conn), attrs) do
        {:ok, batch} -> {:ok, 201, %{data: Serializer.batch(batch, label: true)}}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  def receive_batch(conn, %{"id" => id} = params) do
    idempotent(conn, fn ->
      with {:ok, id} <- parse_id(id),
           {:ok, batch} <- load_batch(conn, id),
           true <- batch.site_id == site_id(conn),
           {:ok, received} <-
             Batches.receive_batch(batch, actor_id(conn), Params.drop_tenant(params)) do
        {:ok, 200, %{data: Serializer.batch(received)}}
      else
        false -> {:error, :not_found}
        other -> other
      end
    end)
  end

  def tests(conn, params) do
    {page, per_page} = Params.page(params)
    tests = LabTests.list_lab_tests(org_id(conn))
    {entries, meta} = Params.slice(tests, page, per_page)
    Response.page(conn, Enum.map(entries, &Serializer.lab_test/1), meta)
  end

  def create_test(conn, params) do
    idempotent(conn, fn ->
      case LabTests.create_lab_test(org_id(conn), Params.drop_tenant(params)) do
        {:ok, test} -> {:ok, 201, %{data: Serializer.lab_test(test)}}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  def update_test(conn, %{"id" => id} = params) do
    idempotent(conn, fn ->
      with {:ok, id} <- parse_id(id),
           {:ok, test} <- load_test(conn, id),
           {:ok, test} <- LabTests.update_lab_test(org_id(conn), test, Params.drop_tenant(params)) do
        {:ok, 200, %{data: Serializer.lab_test(test)}}
      end
    end)
  end

  defp create_lab_order(conn, params, patient_id) do
    tests = params["tests"] || []

    attrs =
      params
      |> Params.drop_tenant()
      |> Map.drop(["tests", "patient_id"])
      |> Map.put("site_id", site_id(conn))

    visit = %{
      patient_id: patient_id,
      site_id: site_id(conn),
      user_id: actor_id(conn),
      visit_type: :lab
    }

    case LabOrders.create_lab_order_with_results(org_id(conn), attrs, tests, visit) do
      {:ok, %{lab_order: order}} ->
        {:ok, 201, %{data: Serializer.lab_order(preload(order, :lab_order_results))}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_batch(conn, id) do
    fetch(fn -> Batches.get_batch!(org_id(conn), id) end)
  end

  defp load_test(conn, id) do
    fetch(fn -> LabTests.get_lab_test!(org_id(conn), id) end)
  end

  defp load_order(conn, id) do
    with {:ok, id} <- parse_id(id),
         {:ok, order} <- fetch(fn -> LabOrders.get_lab_order!(org_id(conn), id) end) do
      if Access.same_site?(scope(conn), order.site_id),
        do: {:ok, order},
        else: {:error, :not_found}
    end
  end

  defp integers(list) when is_list(list) and list != [] do
    list
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case Params.integer(value) do
        {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> unwrap_integers()
  end

  defp integers(_list), do: :error

  defp unwrap_integers({:ok, ids}), do: {:ok, Enum.reverse(ids)}
  defp unwrap_integers(:error), do: :error

  defp money(value) when is_float(value),
    do: :erlang.float_to_binary(value, [:compact, decimals: 2])

  defp money(value), do: value
end
