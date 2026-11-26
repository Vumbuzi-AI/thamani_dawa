defmodule ThamaniDawaWeb.Api.V1.ManufacturerAggregationController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Manufacturing.Operations
  alias ThamaniDawaWeb.Api.FallbackController
  alias ThamaniDawaWeb.Api.Response
  alias ThamaniDawaWeb.Api.V1.Helpers
  alias ThamaniDawaWeb.Plugs.RequireIdempotency
  alias ThamaniDawaWeb.Plugs.RequirePortal

  import Helpers

  action_fallback FallbackController

  plug RequirePortal, :manufacturer

  plug RequireIdempotency
       when action in [
              :start_shipper,
              :prepare_batch,
              :scan_product,
              :request_shipper_sscc,
              :assign_shipper_sscc,
              :verify_shipper,
              :start_pallet,
              :scan_shipper,
              :finish_pallet,
              :allocate_pallet_sscc,
              :verify_pallet
            ]

  def batches(conn, _params) do
    Response.data(conn, %{
      batches: Enum.map(Operations.list_active_batches(org_id(conn)), &batch/1)
    })
  end

  def show_session(conn, %{"id" => id}) do
    case integer(id) do
      {:ok, id} ->
        case Operations.get_session(org_id(conn), id) do
          nil -> {:error, :not_found}
          session -> Response.data(conn, session_payload(session))
        end

      :error ->
        {:error, :not_found}
    end
  end

  def start_shipper(conn, %{"batch_id" => batch_id}) do
    idempotent(conn, fn ->
      with {:ok, batch_id} <- integer(batch_id),
           {:ok, session} <-
             Operations.start_shipper_session(org_id(conn), actor_id(conn), batch_id) do
        {:ok, 201, %{data: session_payload(Operations.get_session(org_id(conn), session.id))}}
      end
    end)
  end

  def prepare_batch(conn, %{"batch_id" => batch_id} = params) do
    idempotent(conn, fn ->
      method = Map.get(params, "method", "during_packing")

      with {:ok, batch_id} <- integer(batch_id),
           {:ok, prepared} <- Operations.prepare_shippers(org_id(conn), batch_id, method) do
        {:ok, 200,
         %{
           data: %{
             batch: batch(prepared.batch),
             sscc_allocation_status: prepared.operation.sscc_allocation_status,
             sscc_quantity: prepared.operation.sscc_quantity
           }
         }}
      end
    end)
  end

  def scan_product(conn, %{"id" => id, "raw" => raw}) do
    idempotent(conn, fn -> result(Operations.capture_product_scan(org_id(conn), id, raw)) end)
  end

  def assign_shipper_sscc(conn, %{"id" => id}) do
    idempotent(conn, fn ->
      session_result(org_id(conn), Operations.assign_shipper_sscc(org_id(conn), id))
    end)
  end

  def request_shipper_sscc(conn, %{"id" => id}) do
    idempotent(conn, fn ->
      case Operations.request_shipper_sscc(org_id(conn), id) do
        {:ok, %{allocation: :available, session: session}} ->
          {:ok, 200,
           %{
             data: %{
               allocation: "available",
               session: session_payload(Operations.get_session(org_id(conn), session.id))
             }
           }}

        {:ok, %{allocation: :pending, session: session}} ->
          {:ok, 202,
           %{
             data: %{
               allocation: "pending",
               session: session_payload(Operations.get_session(org_id(conn), session.id))
             }
           }}

        {:error, _reason} = error ->
          error
      end
    end)
  end

  def verify_shipper(conn, %{"id" => id, "raw" => raw}) do
    idempotent(conn, fn -> result(Operations.verify_shipper_parent(org_id(conn), id, raw)) end)
  end

  def start_pallet(conn, _params) do
    idempotent(conn, fn ->
      with {:ok, session} <- Operations.start_pallet_session(org_id(conn), actor_id(conn)) do
        {:ok, 201, %{data: session_payload(Operations.get_session(org_id(conn), session.id))}}
      end
    end)
  end

  def scan_shipper(conn, %{"id" => id, "raw" => raw}) do
    idempotent(conn, fn -> result(Operations.capture_shipper_scan(org_id(conn), id, raw)) end)
  end

  def finish_pallet(conn, %{"id" => id}) do
    idempotent(conn, fn -> result(Operations.finish_pallet_loading(org_id(conn), id)) end)
  end

  def allocate_pallet_sscc(conn, %{"id" => id} = params) do
    details = Map.take(params, ["order_number", "to_gln", "to_company_name", "to_address"])

    idempotent(conn, fn ->
      result(Operations.allocate_pallet_sscc(org_id(conn), id, details))
    end)
  end

  def verify_pallet(conn, %{"id" => id, "raw" => raw}) do
    idempotent(conn, fn -> result(Operations.verify_pallet_parent(org_id(conn), id, raw)) end)
  end

  defp result({:ok, value}), do: {:ok, 200, %{data: normalize(value)}}
  defp result({:error, _reason} = error), do: error

  defp session_result(organization_id, {:ok, %{id: id}}) do
    {:ok, 200, %{data: session_payload(Operations.get_session(organization_id, id))}}
  end

  defp session_result(_organization_id, {:error, _reason} = error), do: error

  defp normalize(value), do: value

  defp integer(value) when is_integer(value), do: {:ok, value}

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp batch(batch) do
    context = Operations.batch_aggregation_context(batch.organization_id, batch)

    %{
      id: batch.id,
      batch_no: batch.batch_no,
      status: batch.status,
      pack_quantity: batch.pack_quantity,
      packs_per_shipper: batch.packs_per_shipper,
      expected_shipper_count: batch.expected_shipper_count,
      preparation_method: context.preparation_method,
      serialization_completed: context.serialization_completed,
      sscc_allocation_status: context.sscc_allocation_status,
      sscc_quantity: context.sscc_quantity,
      allocated_shipper_count: context.allocated_shipper_count,
      available_shipper_count: context.available_shipper_count,
      sscc_prerequisites_missing: context.sscc_prerequisites_missing,
      aggregation_eligible: context.aggregation_eligible,
      from_gln: batch.from_gln,
      order_number: batch.order_number,
      to_gln: batch.to_gln,
      product: %{id: batch.product.id, gtin: batch.product.gtin, name: batch.product.name}
    }
  end

  defp session_payload(session) do
    context = Operations.session_aggregation_context(session.organization_id, session)

    %{
      id: session.id,
      session_type: session.session_type,
      stage: session.status,
      preparation_method: session.preparation_method,
      expected_item_count: session.expected_item_count,
      captured_item_count: length(session.items),
      capacity_reached: context.capacity_reached,
      allocation_status: context.allocation_status,
      label_ready: context.label_ready,
      expected_parent_sscc: context.expected_parent_sscc,
      parent_verification_pending: context.parent_verification_pending,
      parent_sscc: session.shipper_sscc && session.shipper_sscc.code,
      pallet_sscc: session.pallet && session.pallet.code,
      batch: session.batch && batch(session.batch),
      items:
        Enum.map(session.items, fn item ->
          %{
            raw_identifier: item.raw_identifier,
            serial: item.serial && item.serial.serial,
            shipper_sscc: item.shipper_sscc && item.shipper_sscc.code,
            captured_at: item.captured_at
          }
        end)
    }
  end
end
