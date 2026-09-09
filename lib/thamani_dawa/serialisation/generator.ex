defmodule ThamaniDawa.Serialisation.Generator do
  @moduledoc """
  Runs a generation request against GS1 and records what came back
  (ui.md §11, serialisation.md §4).

  The shape of every run is the same:

    1. write the shipment as `:submitted` **before** the call, so a request
       that times out leaves a visible row to reconcile rather than nothing;
    2. make exactly one call — never a retry, since a retried generation mints
       new codes (§4.5);
    3. persist the issued identifiers in a transaction and settle the shipment
       to `:issued`, or to `:failed` with GS1's own message.

  Nothing here mints an identifier or invents a missing one: a response we
  cannot find an SSCC in is a failure, not a locally-filled gap (§2.4.1).
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Gs1Api
  alias ThamaniDawa.Gs1Api.Error
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Serialisation.Response
  alias ThamaniDawa.Serialisation.SerialisedCode
  alias ThamaniDawa.Serialisation.SerialisedRequest
  alias ThamaniDawa.Serialisation.SerializationLog
  alias ThamaniDawa.Serialisation.Shipment
  alias ThamaniDawa.Serialisation.ShipmentLine
  alias ThamaniDawa.Serialisation.Sscc
  alias ThamaniDawa.Serialisation.SsccItem
  alias ThamaniDawa.Serialisation.SsccRequest

  @doc """
  Generates one SSCC for a single GTIN and batch.

  Returns `{:ok, shipment, sscc}` with the issued SSCC, or `{:error, error}`
  carrying GS1's member-facing message.
  """
  @spec generate_sscc(Scope.t(), SsccRequest.t()) ::
          {:ok, Shipment.t(), Sscc.t()} | {:error, Error.t() | atom() | Ecto.Changeset.t()}
  def generate_sscc(%Scope{} = scope, %SsccRequest{} = request) do
    with {:ok, shipment} <- open_shipment(scope, SsccRequest.to_shipment_attrs(request), request),
         {:ok, body} <-
           call(shipment, &Gs1Api.create_sscc(scope, &1), SsccRequest.to_params(request)),
         {:ok, issued} <- Response.sscc(body) do
      record_sscc(scope, shipment, request, issued)
    end
  end

  @doc """
  Generates serialised Data Matrix codes for a GTIN: one pallet SSCC, a
  shipper per `shipper_qty` trade items, and a serial per trade item.

  Returns `{:ok, shipment, pallet_sscc}` — the pallet is what Screen D groups
  by, so the caller can land the member on the group it just created.
  """
  @spec generate_serialised(Scope.t(), SerialisedRequest.t()) ::
          {:ok, Shipment.t(), Sscc.t()} | {:error, Error.t() | atom() | Ecto.Changeset.t()}
  def generate_serialised(%Scope{} = scope, %SerialisedRequest{} = request) do
    with {:ok, params} <- SerialisedRequest.to_params(request),
         {:ok, shipment} <-
           open_shipment(scope, SerialisedRequest.to_shipment_attrs(request), request),
         {:ok, body} <-
           call(shipment, &Gs1Api.create_serialised_datamatrix(scope, &1), params),
         {:ok, issued} <- Response.serialised(body) do
      record_serialised(scope, shipment, request, issued)
    end
  end

  # The row exists before the call so an ambiguous timeout is recoverable: a
  # `:submitted` shipment with no codes is exactly the reconciliation state
  # ui.md §11.7 asks the UI to show.
  defp open_shipment(%Scope{} = scope, attrs, request) do
    attrs =
      Map.merge(attrs, %{
        organization_id: scope.organization_id,
        user_id: scope.user && scope.user.id,
        status: :submitted
      })

    Multi.new()
    |> Multi.insert(:shipment, Shipment.changeset(%Shipment{}, attrs))
    |> Multi.insert(:line, fn %{shipment: shipment} ->
      ShipmentLine.changeset(%ShipmentLine{}, %{
        shipment_id: shipment.id,
        gtin: request.gtin,
        cases: cases_for(request),
        items_per_case: items_per_case_for(request)
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{shipment: shipment}} -> {:ok, shipment}
      {:error, _step, changeset, _changes} -> {:error, changeset}
    end
  end

  defp cases_for(%SerialisedRequest{} = request), do: SerialisedRequest.shipper_count(request)
  defp cases_for(%SsccRequest{}), do: 1

  defp items_per_case_for(%SerialisedRequest{shipper_qty: qty}), do: qty
  defp items_per_case_for(%SsccRequest{count_of_trade_items: count}), do: count

  defp call(shipment, fun, params) do
    case fun.(params) do
      {:ok, body} ->
        {:ok, body}

      {:error, reason} ->
        fail(shipment, reason)
        {:error, reason}
    end
  end

  defp fail(shipment, reason) do
    shipment
    |> Shipment.changeset(%{status: :failed})
    |> Repo.update()

    reason
  end

  defp record_sscc(scope, shipment, request, issued) do
    Multi.new()
    |> Multi.insert(
      :sscc,
      Sscc.changeset(%Sscc{}, %{
        organization_id: scope.organization_id,
        shipment_id: shipment.id,
        code: issued.code,
        level: :pallet,
        extension_digit: issued.extension_digit,
        image: issued.image,
        issued_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
    )
    |> Multi.insert(:item, fn %{sscc: sscc} ->
      SsccItem.changeset(%SsccItem{}, %{
        sscc_id: sscc.id,
        gtin: request.gtin,
        count: request.count_of_trade_items,
        items: request.count_of_trade_items
      })
    end)
    |> settle(shipment)
    |> Multi.insert(
      :log,
      SerializationLog.changeset(%SerializationLog{}, %{
        organization_id: scope.organization_id,
        user_id: scope.user && scope.user.id,
        shipment_id: shipment.id,
        type: :sscc,
        gtin: request.gtin,
        batch: request.batch,
        count: 1
      })
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{settle: settled, sscc: sscc}} ->
        {:ok, settled, Repo.preload(sscc, :items)}

      {:error, _step, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp record_serialised(scope, shipment, request, issued) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Multi.new()
    |> Multi.insert(
      :pallet,
      Sscc.changeset(%Sscc{}, %{
        organization_id: scope.organization_id,
        shipment_id: shipment.id,
        code: issued.pallet_sscc,
        level: :pallet,
        extension_digit: issued.extension_digit,
        issued_at: now
      })
    )
    |> Multi.insert(:pallet_item, fn %{pallet: pallet} ->
      SsccItem.changeset(%SsccItem{}, %{
        sscc_id: pallet.id,
        gtin: request.gtin,
        count: request.trade_item_qty,
        items: request.trade_item_qty
      })
    end)
    |> Multi.run(:shippers, fn repo, %{pallet: pallet} ->
      insert_shippers(repo, scope, shipment, request, pallet, issued.shippers, now)
    end)
    |> settle(shipment)
    |> Multi.insert(
      :log,
      SerializationLog.changeset(%SerializationLog{}, %{
        organization_id: scope.organization_id,
        user_id: scope.user && scope.user.id,
        shipment_id: shipment.id,
        type: :serialised,
        gtin: request.gtin,
        batch: request.batch,
        count: Enum.sum(Enum.map(issued.shippers, &length(&1.primary_serials)))
      })
    )
    |> Repo.transaction(timeout: :infinity)
    |> case do
      {:ok, %{settle: settled, pallet: pallet}} -> {:ok, settled, pallet}
      {:error, _step, changeset, _changes} -> {:error, changeset}
    end
  end

  defp insert_shippers(repo, scope, shipment, request, pallet, shippers, now) do
    Enum.reduce_while(shippers, {:ok, []}, fn shipper, {:ok, acc} ->
      case insert_shipper(repo, scope, shipment, request, pallet, shipper, now) do
        {:ok, inserted} -> {:cont, {:ok, [inserted | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp insert_shipper(repo, scope, shipment, request, pallet, shipper, now) do
    changeset =
      Sscc.changeset(%Sscc{}, %{
        organization_id: scope.organization_id,
        shipment_id: shipment.id,
        parent_sscc_id: pallet.id,
        code: shipper.sscc,
        level: :case,
        serial: shipper.serial,
        issued_at: now
      })

    with {:ok, case_sscc} <- repo.insert(changeset),
         {:ok, _item} <-
           repo.insert(
             SsccItem.changeset(%SsccItem{}, %{
               sscc_id: case_sscc.id,
               gtin: request.gtin,
               count: length(shipper.primary_serials),
               items: length(shipper.primary_serials)
             })
           ) do
      insert_primaries(repo, scope, shipment, request, case_sscc, shipper.primary_serials, now)
      {:ok, case_sscc}
    end
  end

  # Inserted in chunks: a run can carry hundreds of thousands of serials, which
  # is far past what one parameterised INSERT can take.
  defp insert_primaries(repo, scope, shipment, request, case_sscc, serials, now) do
    serials
    |> Enum.chunk_every(1_000)
    |> Enum.each(fn chunk ->
      rows =
        Enum.map(chunk, fn serial ->
          %{
            organization_id: scope.organization_id,
            shipment_id: shipment.id,
            sscc_id: case_sscc.id,
            gtin: request.gtin,
            serial: serial,
            inserted_at: now,
            updated_at: now
          }
        end)

      repo.insert_all(SerialisedCode, rows)
    end)
  end

  defp settle(multi, shipment) do
    Multi.update(multi, :settle, Shipment.changeset(shipment, %{status: :issued}))
  end
end
