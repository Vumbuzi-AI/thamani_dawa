defmodule ThamaniDawa.Manufacturing.Operations do
  @moduledoc """
  Device-independent manufacturer operations.

  This module is the single authority for physical aggregation.  Web pages
  and the mobile API deliberately call these functions rather than retaining
  their own counters or parent/child rules in the presentation layer.
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.Epcis
  alias ThamaniDawa.GS1.MemberApi
  alias ThamaniDawa.GS1Decoder

  alias ThamaniDawa.Manufacturing.{
    AggregationSession,
    AggregationSessionItem,
    Batch,
    GenerationOperation,
    Pallet,
    Product,
    Serial,
    ShipperSscc,
    SsccBatch
  }

  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Repo

  @active_session_statuses ~w(scanning awaiting_sscc awaiting_label_verification)

  @doc "PubSub topic for generation updates on a product."
  def product_topic(product_id), do: "manufacturing:product:#{product_id}"

  @doc "Subscribes the caller to generation updates for a product."
  def subscribe_product(product_id) do
    Phoenix.PubSub.subscribe(ThamaniDawa.PubSub, product_topic(product_id))
  end

  @doc """
  Returns the latest in-flight (or recently failed for `batch_no`) generation
  operation + batch for a product, if any.
  """
  def generation_status_for_product(organization_id, product_id, batch_no \\ nil) do
    base =
      from o in GenerationOperation,
        join: b in assoc(o, :batch),
        where: o.organization_id == ^organization_id and o.manufacturer_product_id == ^product_id,
        order_by: [desc: o.inserted_at, desc: o.id],
        limit: 1,
        preload: [batch: b]

    query =
      if is_binary(batch_no) and batch_no != "" do
        where(base, [_o, b], b.batch_no == ^batch_no)
      else
        where(base, [o, _b], o.serial_allocation_status in ["pending", "allocating"])
      end

    case Repo.one(query) do
      %GenerationOperation{serial_allocation_status: status} = op
      when status in ["pending", "allocating", "failed", "reconciliation_required"] ->
        op

      _other ->
        nil
    end
  end

  # Identifier allocation ---------------------------------------------------

  @doc "Creates a durable, explicit identifier-allocation intent for a batch."
  def prepare_generation(organization_id, product_id, attrs) do
    Repo.transaction(fn ->
      product = Repo.get_by!(Product, id: product_id, organization_id: organization_id)

      batch_attrs = normalize_batch_attrs(attrs)

      batch =
        %Batch{organization_id: organization_id, manufacturer_product_id: product.id}
        |> Batch.changeset(Map.put(batch_attrs, :status, "prepared"))
        |> Repo.insert!()

      operation =
        %GenerationOperation{
          organization_id: organization_id,
          manufacturer_product_id: product.id,
          manufacturer_batch_id: batch.id
        }
        |> GenerationOperation.changeset(%{
          operation_key: Ecto.UUID.generate(),
          serial_quantity: batch.pack_quantity,
          # Serialization is deliberately independent from shipper preparation.
          # A shipper SSCC is minted only after the mobile app has scanned a
          # complete shipper, so GS1 receives the aggregation in the same call.
          sscc_quantity: 0,
          status: "pending",
          serial_allocation_status: "pending",
          sscc_allocation_status: "not_required",
          serial_request_payload: serial_request_payload(product, batch)
        })
        |> Repo.insert!()

      %{batch: batch, operation: operation}
    end)
  end

  @doc "Queues a prepared allocation intent exactly once; it never retries a remote create request."
  def enqueue_generation(%GenerationOperation{} = operation) do
    %{operation_id: operation.id}
    |> ThamaniDawa.Manufacturing.IdentifierAllocationWorker.new()
    |> Oban.insert()
  end

  @doc "Marks a persisted intent as in progress and allocates identifiers once."
  def allocate_identifiers(operation_id) do
    with {:ok, operation} <- claim_operation(operation_id),
         do: allocate_claimed_operation(operation)
  end

  defp claim_operation(operation_id) do
    Repo.transaction(fn ->
      operation =
        Repo.one!(from o in GenerationOperation, where: o.id == ^operation_id, lock: "FOR UPDATE")

      # Serialize the transition from a harmless draft into an operational
      # batch. The partial unique index is the durable backstop; the product
      # lock keeps two simultaneous explicit generation requests from both
      # reaching a non-idempotent remote allocation call.
      _product =
        Repo.one!(
          from p in Product,
            where: p.id == ^operation.manufacturer_product_id,
            lock: "FOR UPDATE"
        )

      cond do
        operation.status == "reconciliation_required" ->
          Repo.rollback(:not_actionable)

        operation.serial_allocation_status == "pending" ->
          operation =
            operation
            |> Ecto.Changeset.change(
              status: "allocating",
              serial_allocation_status: "allocating",
              started_at: DateTime.utc_now() |> DateTime.truncate(:second)
            )
            |> Repo.update!()

          batch = Repo.get!(Batch, operation.manufacturer_batch_id)
          batch |> Ecto.Changeset.change(status: "allocating") |> Repo.update!()
          operation

        operation.serial_allocation_status == "completed" and
            operation.sscc_allocation_status == "pending" ->
          # Take the SSCC lease under the same lock used for serial allocation.
          # A second job for this operation must not issue a second non-idempotent
          # GS1 create request.
          operation
          |> Ecto.Changeset.change(
            status: "allocating",
            sscc_allocation_status: "allocating",
            sscc_attempted_at: DateTime.utc_now() |> DateTime.truncate(:second)
          )
          |> Repo.update!()

        operation.serial_allocation_status == "completed" and
            operation.sscc_allocation_status == "allocating" ->
          Repo.rollback(:not_actionable)

        true ->
          Repo.rollback(:not_actionable)
      end
    end)
  end

  defp allocate_claimed_operation(operation) do
    operation = Repo.preload(operation, [:product, :batch])

    case operation.serial_allocation_status do
      "allocating" -> allocate_serials(operation)
      "completed" -> allocate_remaining_ssccs(operation)
    end
  end

  defp allocate_serials(operation) do
    token = Organizations.gs1_api_key(operation.organization_id)

    case MemberApi.create_serials(operation.serial_request_payload, api_token: token) do
      {:ok, response} ->
        handle_serial_response(operation, response)

      {:error, :unavailable} ->
        mark_generation_reconciliation(
          operation,
          "We couldn't confirm whether GS1 created the serials for this batch"
        )

      {:error, reason} ->
        mark_generation_failed(operation, rejected_gs1_note(:serial, reason))
    end
  end

  defp handle_serial_response(operation, response) do
    case serial_values(response) do
      {:ok, values} when length(values) == operation.serial_quantity ->
        result =
          Repo.transaction(fn ->
            persist_serial_allocation!(operation, response, values)
          end)

        case result do
          {:ok, operation} ->
            complete_generation(operation)

          {:error, _reason} ->
            # GS1 has already minted the serials. A local failure cannot undo
            # that, so the intent must be reconciled rather than retried.
            mark_generation_reconciliation(
              operation,
              "GS1 created the serials, but we couldn't save them here"
            )
        end

      {:ok, _values} ->
        mark_generation_reconciliation(
          operation,
          "GS1 returned a different number of serials than this batch requested"
        )

      {:error, reason} ->
        mark_generation_reconciliation(operation, unexpected_response_note(:serial, reason))
    end
  end

  defp persist_serial_allocation!(operation, response, values) do
    persisted = persist_serials!(operation, values)

    operation =
      operation
      |> Ecto.Changeset.change(
        serial_allocation_status: "completed",
        serial_response: response
      )
      |> Repo.update!()

    batch = operation.batch |> Ecto.Changeset.change(status: "prepared") |> Repo.update!()

    Epcis.record_manufacturer_commission(
      operation.organization_id,
      operation.product,
      batch,
      persisted,
      batch.from_gln
    )

    operation
  end

  defp allocate_remaining_ssccs(operation) do
    operation = Repo.preload(operation, [:product, :batch])
    allocated = count_batch_shippers(operation.organization_id, operation.batch.id)

    cond do
      allocated >= operation.sscc_quantity ->
        complete_generation(operation)

      is_nil(operation.sscc_request_payload) ->
        mark_generation_reconciliation(
          operation,
          "The SSCC intent has no serial snapshot; no safe GS1 request can be reconstructed"
        )

      not shipper_request_possible?(operation.batch) ->
        mark_generation_failed(
          operation,
          "A valid destination GLN is needed before GS1 can create a shipper label",
          :sscc
        )

      true ->
        allocate_one_shipper(operation)
    end
  end

  defp allocate_one_shipper(operation) do
    token = Organizations.gs1_api_key(operation.organization_id)

    case MemberApi.create_shipper_sscc(operation.sscc_request_payload, api_token: token) do
      {:ok, code} ->
        transaction_result =
          Repo.transaction(fn ->
            persist_available_shipper!(operation, code, operation.sscc_request_payload)
          end)

        case transaction_result do
          {:ok, _shipper} ->
            allocate_remaining_ssccs(operation)

          {:error, _reason} ->
            # The remote SSCC exists even though the local record failed.
            mark_generation_reconciliation(
              operation,
              "GS1 created a shipper label, but we couldn't save it here; earlier labels are safe"
            )
        end

      {:error, :unavailable} ->
        mark_generation_reconciliation(
          operation,
          "We couldn't confirm whether GS1 created the last shipper label; earlier labels are safe"
        )

      {:error, reason} ->
        mark_generation_failed(
          operation,
          rejected_gs1_note(:shipper, reason),
          :sscc
        )
    end
  end

  defp complete_generation(operation) do
    result =
      Repo.transaction(fn ->
        operation = Repo.get!(GenerationOperation, operation.id)
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        sscc_status =
          if operation.sscc_quantity == 0,
            do: "not_required",
            else: "completed"

        operation
        |> Ecto.Changeset.change(
          status: "completed",
          sscc_allocation_status: sscc_status,
          completed_at: now
        )
        |> Repo.update!()
      end)

    case result do
      {:ok, updated} ->
        broadcast_generation_update(updated)
        {:ok, updated}

      other ->
        other
    end
  end

  @doc """
  Marks a serialized batch as ready for mobile packing.

  No identifier is allocated here. A shipper SSCC is requested only after the
  mobile app has scanned a complete shipper, so the GS1 call carries the serial
  aggregation. The `method` argument is retained for API compatibility and must
  be `during_packing`.
  """
  def prepare_shippers(organization_id, batch_id, "during_packing") do
    unwrap_transaction(
      Repo.transaction(fn ->
        batch =
          Repo.one!(
            from b in Batch,
              where: b.id == ^batch_id and b.organization_id == ^organization_id,
              lock: "FOR UPDATE"
          )

        ensure_serialization_completed!(organization_id, batch.id)
        ensure_method_not_locked!(batch)

        batch =
          batch
          |> Ecto.Changeset.change(shipper_preparation_method: "during_packing")
          |> Repo.update!()

        %{
          batch: Repo.preload(batch, :product),
          operation: latest_generation_operation!(organization_id, batch.id)
        }
      end)
    )
  end

  def prepare_shippers(_organization_id, _batch_id, _method),
    do: {:error, :unsupported_preparation_method}

  defp ensure_method_not_locked!(batch) do
    if batch.aggregation_started_at && batch.shipper_preparation_method != "during_packing",
      do: Repo.rollback({:error, :preparation_method_locked}),
      else: :ok
  end

  defp mark_generation_reconciliation(operation, note) do
    result =
      Repo.transaction(fn ->
        operation = Repo.get!(GenerationOperation, operation.id)
        batch = Repo.get!(Batch, operation.manufacturer_batch_id)

        operation =
          operation
          |> Ecto.Changeset.change(
            status: "reconciliation_required",
            serial_allocation_status: reconciliation_status(operation.serial_allocation_status),
            sscc_allocation_status: reconciliation_status(operation.sscc_allocation_status),
            reconciliation_note: note
          )
          |> Repo.update!()

        batch |> Ecto.Changeset.change(status: "allocating") |> Repo.update!()
        operation
      end)

    if match?({:ok, _}, result) do
      {:ok, updated} = result
      broadcast_generation_update(updated)
    end

    result
  end

  @doc """
  Resolves an uncertain product-serial request by asking GS1 what it actually
  created. Confirmed serials are imported and the batch is completed; when GS1
  has none, the same intent is safely re-armed for another attempt.
  """
  def reconcile_serial_allocation(operation_id) do
    operation =
      GenerationOperation
      |> Repo.get!(operation_id)
      |> Repo.preload([:product, :batch])

    if operation.serial_allocation_status != "reconciliation_required" do
      {:error, :not_reconcilable}
    else
      with {:ok, serials} <- remote_serials(operation) do
        cond do
          length(serials) >= operation.serial_quantity ->
            import_confirmed_serials(operation, serials)

          serials == [] ->
            rearm_serial_allocation(operation)

          true ->
            {:error, {:partial_allocation, length(serials), operation.serial_quantity}}
        end
      end
    end
  end

  defp remote_serials(operation) do
    token = Organizations.gs1_api_key(operation.organization_id)

    with {:ok, results} <-
           MemberApi.batch_serials(
             operation.product.gtin,
             operation.batch.batch_no,
             api_token: token
           ) do
      serials =
        results
        |> Enum.map(&Map.get(&1, "serial"))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      {:ok, serials}
    end
  end

  defp import_confirmed_serials(operation, serials) do
    response = %{
      "result" => "success",
      "primary_datamatrices" => Enum.map(serials, &%{"serial" => &1})
    }

    result =
      Repo.transaction(fn ->
        persist_serial_allocation!(operation, response, serials)
      end)

    case result do
      {:ok, operation} ->
        case complete_generation(operation) do
          {:ok, updated} -> {:ok, %{result: :recovered, operation: updated}}
          error -> error
        end

      error ->
        error
    end
  end

  defp rearm_serial_allocation(operation) do
    result =
      Repo.transaction(fn ->
        operation
        |> Ecto.Changeset.change(
          status: "pending",
          serial_allocation_status: "pending",
          reconciliation_note: nil
        )
        |> Repo.update!()

        operation.batch
        |> Ecto.Changeset.change(status: "prepared")
        |> Repo.update!()
      end)

    case result do
      {:ok, _} ->
        case enqueue_generation(operation) do
          {:ok, _job} ->
            {:ok, %{result: :retry_scheduled, operation: operation}}

          {:error, reason} ->
            mark_generation_reconciliation(
              operation,
              "GS1 confirmed no serials were created for this batch, but we couldn't try again just now"
            )

            {:error, reason}
        end

      error ->
        error
    end
  end

  defp reconciliation_status("completed"), do: "completed"
  defp reconciliation_status(_status), do: "reconciliation_required"

  defp mark_generation_failed(operation, note, allocation \\ :serial) do
    allocation_changes =
      case allocation do
        :serial -> [serial_allocation_status: "failed"]
        :sscc -> [sscc_allocation_status: "failed"]
      end

    result =
      operation
      |> Ecto.Changeset.change(
        [status: "failed", reconciliation_note: note] ++ allocation_changes
      )
      |> Repo.update()

    if match?({:ok, _}, result) do
      {:ok, updated} = result
      broadcast_generation_update(updated)
    end

    result
  end

  defp broadcast_generation_update(operation) do
    Phoenix.PubSub.broadcast(
      ThamaniDawa.PubSub,
      product_topic(operation.manufacturer_product_id),
      {:generation_updated, operation.id}
    )
  end

  # Shipper sessions --------------------------------------------------------

  def start_shipper_session(organization_id, user_id, batch_id) do
    unwrap_transaction(
      Repo.transaction(fn ->
        batch =
          Repo.one!(
            from b in Batch,
              where: b.id == ^batch_id and b.organization_id == ^organization_id,
              lock: "FOR UPDATE"
          )

        ensure_batch_ready!(batch)
        ensure_no_active_session!(organization_id, "shipper", batch.id)
        ensure_preparation_selected!(batch.shipper_preparation_method)

        # create_shipper_sscc needs a genuine destination GLN. Detect that before
        # physical packing starts instead of after a full shipper has been filled.
        if available_shipper_count(organization_id, batch.id) == 0 and
             not shipper_request_possible?(batch) do
          Repo.rollback({:error, :sscc_prerequisites_missing})
        end

        now = DateTime.utc_now() |> DateTime.truncate(:second)

        session =
          %AggregationSession{
            organization_id: organization_id,
            manufacturer_batch_id: batch.id,
            created_by_id: user_id
          }
          |> AggregationSession.changeset(%{
            session_type: "shipper",
            status: "scanning",
            preparation_method: "during_packing",
            expected_item_count: batch.packs_per_shipper,
            manufacturer_shipper_sscc_id: nil
          })
          |> Repo.insert!()

        batch
        |> Ecto.Changeset.change(
          status: "aggregating",
          aggregation_started_at: batch.aggregation_started_at || now
        )
        |> Repo.update!()

        session
      end)
    )
  end

  def capture_product_scan(organization_id, session_id, raw_identifier) do
    unwrap_transaction(
      Repo.transaction(fn ->
        session = locked_session!(organization_id, session_id, "shipper")
        ensure_status!(session, "scanning")
        batch = Repo.preload(session, batch: :product).batch
        identifier = parse_product_identifier!(raw_identifier)
        ensure_product_identifier!(identifier, batch)

        serial =
          Repo.one(
            from s in Serial,
              where:
                s.organization_id == ^organization_id and s.manufacturer_batch_id == ^batch.id and
                  s.serial == ^identifier.serial,
              lock: "FOR UPDATE"
          )

        if is_nil(serial), do: Repo.rollback({:error, :unknown_serial})

        if serial.manufacturer_shipper_sscc_id, do: Repo.rollback({:error, :already_aggregated})

        item =
          %AggregationSessionItem{}
          |> AggregationSessionItem.changeset(%{
            manufacturer_aggregation_session_id: session.id,
            manufacturer_serial_id: serial.id,
            raw_identifier: raw_identifier,
            captured_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })
          |> Repo.insert()

        case item do
          {:ok, _item} -> advance_shipper_when_full!(session)
          {:error, changeset} -> Repo.rollback(scan_error(changeset))
        end
      end)
    )
  end

  def assign_shipper_sscc(organization_id, session_id) do
    unwrap_transaction(
      Repo.transaction(fn ->
        session = locked_session!(organization_id, session_id, "shipper")
        ensure_status!(session, "awaiting_sscc")
        batch = Repo.preload(session, :batch).batch

        shipper = available_shipper!(organization_id, batch.id)

        now = DateTime.utc_now() |> DateTime.truncate(:second)

        shipper
        |> Ecto.Changeset.change(
          status: "awaiting_verification",
          assigned_at: now,
          label_prepared_at: now
        )
        |> Repo.update!()

        session
        |> AggregationSession.changeset(%{
          status: "awaiting_label_verification",
          manufacturer_shipper_sscc_id: shipper.id
        })
        |> Repo.update!()
        |> Repo.preload([:shipper_sscc, :pallet])
      end)
    )
  rescue
    Ecto.NoResultsError -> {:error, :no_available_sscc}
  end

  @doc """
  Requests the shipper SSCC after a session reaches capacity.

  The request snapshots the scanned serials into a persisted allocation intent.
  The worker calls GS1 `create_shipper_sscc` with that snapshot so the remote
  ERP receives the aggregation in the same operation that mints the SSCC. A
  later `assign_shipper_sscc/2` claims the confirmed shipper for label printing.
  """
  def request_shipper_sscc(organization_id, session_id) do
    result =
      Repo.transaction(fn ->
        session = locked_session!(organization_id, session_id, "shipper")
        ensure_status!(session, "awaiting_sscc")
        batch = Repo.preload(session, :batch).batch
        arm_next_shipper_sscc(organization_id, session, batch)
      end)

    case result do
      {:ok, %{allocation: :pending, operation: operation} = request} ->
        case enqueue_generation(operation) do
          {:ok, _job} ->
            {:ok, request |> Map.delete(:operation) |> Map.delete(:previous_sscc_status)}

          {:error, reason} ->
            # Nothing can process the intent without a job. Release the lease
            # so a later request arms and enqueues it again rather than
            # returning :pending forever.
            release_armed_sscc(operation, request.previous_sscc_status)
            {:error, reason}
        end

      {:ok, request} ->
        {:ok, request}

      error ->
        error
    end
  end

  defp release_armed_sscc(operation, previous_status) do
    operation
    |> Ecto.Changeset.change(
      status: "completed",
      sscc_allocation_status: previous_status,
      reconciliation_note: nil
    )
    |> Repo.update!()
  end

  defp arm_next_shipper_sscc(organization_id, session, batch) do
    if available_shipper_count(organization_id, batch.id) > 0 do
      %{session: session, allocation: :available}
    else
      arm_missing_shipper_sscc(organization_id, session, batch)
    end
  end

  defp arm_missing_shipper_sscc(organization_id, session, batch) do
    ensure_shipper_request_possible!(batch)
    operation = latest_generation_operation!(organization_id, batch.id)
    ensure_not_reconciliation_required!(operation)

    if operation.sscc_allocation_status in ["pending", "allocating"] do
      # A repeated request must not issue a second create for the same shipper.
      reconcile_stale_sscc_attempt!(operation)
      %{session: session, allocation: :pending}
    else
      previous_status = operation.sscc_allocation_status
      operation = arm_fresh_shipper_sscc!(operation, organization_id, session, batch)

      %{
        session: session,
        allocation: :pending,
        operation: operation,
        previous_sscc_status: previous_status
      }
    end
  end

  defp reconcile_stale_sscc_attempt!(%{sscc_allocation_status: "allocating"} = operation) do
    if stale_sscc_attempt?(operation) do
      operation
      |> Ecto.Changeset.change(
        status: "reconciliation_required",
        sscc_allocation_status: "reconciliation_required",
        reconciliation_note:
          "We couldn't confirm whether GS1 created this shipper label; check before trying again"
      )
      |> Repo.update!()
    else
      operation
    end
  end

  defp reconcile_stale_sscc_attempt!(operation), do: operation

  defp arm_fresh_shipper_sscc!(operation, organization_id, session, batch) do
    payload = shipper_request_payload(organization_id, session, batch)
    confirmed = count_batch_shippers(organization_id, batch.id)

    operation
    |> Ecto.Changeset.change(
      sscc_quantity: confirmed + 1,
      sscc_allocation_status: "pending",
      status: "allocating",
      sscc_request_payload: payload,
      sscc_attempted_at: nil,
      reconciliation_note: nil
    )
    |> Repo.update!()
  end

  @sscc_lease_timeout :timer.minutes(15)

  defp stale_sscc_attempt?(%{sscc_attempted_at: %DateTime{} = attempted_at}) do
    DateTime.compare(
      attempted_at,
      DateTime.add(DateTime.utc_now(), -@sscc_lease_timeout, :second)
    ) == :lt
  end

  defp stale_sscc_attempt?(_operation), do: false

  defp shipper_request_payload(organization_id, session, batch) do
    serial_ids =
      Enum.map(session_items!(session.id, :serial), & &1.manufacturer_serial_id)

    serials =
      Repo.all(
        from s in Serial,
          where: s.id in ^serial_ids and s.organization_id == ^organization_id,
          order_by: [asc: s.serial],
          select: s.serial
      )

    if length(serials) != session.expected_item_count,
      do: Repo.rollback({:error, :capacity_not_reached})

    product = Repo.get!(Product, batch.manufacturer_product_id)

    %{
      "barcode" => product.gtin,
      "material_description" => shipper_material_description(product),
      "serials" => serials,
      "from" => %{"gln" => batch.from_gln},
      "to" => %{"gln" => batch.to_gln}
    }
    |> maybe_put_order_number(batch.order_number)
  end

  defp maybe_put_order_number(payload, order_number)
       when is_binary(order_number) and byte_size(order_number) > 0,
       do: Map.put(payload, "order_number", order_number)

  defp maybe_put_order_number(payload, _order_number), do: payload

  defp shipper_material_description(%Product{description: description, name: name}) do
    if is_binary(description) and String.trim(description) != "",
      do: String.trim(description),
      else: name
  end

  defp ensure_shipper_request_possible!(batch) do
    if shipper_request_possible?(batch),
      do: :ok,
      else: Repo.rollback({:error, :sscc_prerequisites_missing})
  end

  defp ensure_not_reconciliation_required!(operation) do
    if operation.sscc_allocation_status == "reconciliation_required",
      do: Repo.rollback({:error, :reconciliation_required}),
      else: :ok
  end

  def verify_shipper_parent(organization_id, session_id, raw_identifier) do
    unwrap_transaction(
      Repo.transaction(fn ->
        session = locked_session!(organization_id, session_id, "shipper")
        ensure_status!(session, "awaiting_label_verification")
        shipper = Repo.get!(ShipperSscc, session.manufacturer_shipper_sscc_id)
        scanned = parse_sscc!(raw_identifier)
        if scanned != shipper.code, do: Repo.rollback({:error, :parent_mismatch})

        items = session_items!(session.id, :serial)

        if length(items) != session.expected_item_count,
          do: Repo.rollback({:error, :capacity_not_reached})

        serial_ids = Enum.map(items, & &1.manufacturer_serial_id)

        {updated, _} =
          Repo.update_all(
            from(s in Serial,
              where: s.id in ^serial_ids and is_nil(s.manufacturer_shipper_sscc_id)
            ),
            set: [manufacturer_shipper_sscc_id: shipper.id]
          )

        if updated != length(serial_ids), do: Repo.rollback({:error, :already_aggregated})

        now = DateTime.utc_now() |> DateTime.truncate(:second)
        serials = Repo.all(from s in Serial, where: s.id in ^serial_ids)

        shipper
        |> Ecto.Changeset.change(
          status: "completed",
          packed_serials: Enum.map(serials, & &1.serial),
          count_of_trade_items: length(serials),
          verified_at: now,
          completed_at: now,
          trackiq_status: "pending"
        )
        |> Repo.update!()

        session
        |> AggregationSession.changeset(%{
          status: "completed",
          parent_verified_at: now,
          completed_at: now
        })
        |> Repo.update!()

        product =
          Repo.get!(
            Product,
            Repo.get!(Batch, session.manufacturer_batch_id).manufacturer_product_id
          )

        Epcis.record_manufacturer_serial_pack(
          organization_id,
          product,
          shipper,
          serials,
          shipper.from_gln
        )

        %{session_id: session.id, shipper_id: shipper.id, status: "completed"}
      end)
    )
  end

  # Pallet sessions ---------------------------------------------------------

  def start_pallet_session(organization_id, user_id) do
    unwrap_transaction(
      Repo.transaction(fn ->
        ensure_no_active_session!(organization_id, "pallet", nil)

        %AggregationSession{organization_id: organization_id, created_by_id: user_id}
        |> AggregationSession.changeset(%{session_type: "pallet", status: "scanning"})
        |> Repo.insert!()
      end)
    )
  end

  def capture_shipper_scan(organization_id, session_id, raw_identifier) do
    unwrap_transaction(
      Repo.transaction(fn ->
        session = locked_session!(organization_id, session_id, "pallet")
        ensure_status!(session, "scanning")
        code = parse_sscc!(raw_identifier)

        shipper =
          Repo.one(
            from s in ShipperSscc,
              where: s.organization_id == ^organization_id and s.code == ^code,
              lock: "FOR UPDATE"
          ) || Repo.rollback({:error, :unknown_shipper})

        ensure_pallet_eligible!(session, shipper)

        item =
          %AggregationSessionItem{}
          |> AggregationSessionItem.changeset(%{
            manufacturer_aggregation_session_id: session.id,
            manufacturer_shipper_sscc_id: shipper.id,
            raw_identifier: raw_identifier,
            captured_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })
          |> Repo.insert()

        case item do
          {:ok, _item} -> session_summary(session.id)
          {:error, changeset} -> Repo.rollback(scan_error(changeset))
        end
      end)
    )
  end

  def finish_pallet_loading(organization_id, session_id) do
    unwrap_transaction(
      Repo.transaction(fn ->
        session = locked_session!(organization_id, session_id, "pallet")
        ensure_status!(session, "scanning")
        if session_item_count(session.id) == 0, do: Repo.rollback({:error, :no_shippers_captured})

        now = DateTime.utc_now() |> DateTime.truncate(:second)

        session
        |> AggregationSession.changeset(%{status: "awaiting_sscc", finished_loading_at: now})
        |> Repo.update!()
      end)
    )
  end

  @doc "Called by the allocation worker after loading is deliberately finished."
  def allocate_pallet_sscc(organization_id, session_id) do
    session =
      Repo.one!(
        from s in AggregationSession,
          where: s.id == ^session_id and s.organization_id == ^organization_id
      )

    if session.status != "awaiting_sscc",
      do: {:error, :not_actionable},
      else: do_allocate_pallet_sscc(session)
  end

  defp do_allocate_pallet_sscc(session) do
    shippers = captured_shippers(session.id)

    with {:ok, context} <- pallet_context(shippers),
         {:ok, code} <-
           MemberApi.create_sscc(context.params,
             api_token: Organizations.gs1_api_key(session.organization_id)
           ) do
      unwrap_transaction(
        Repo.transaction(fn ->
          session = locked_session!(session.organization_id, session.id, "pallet")
          ensure_status!(session, "awaiting_sscc")
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          pallet =
            %Pallet{organization_id: session.organization_id}
            |> Pallet.changeset(
              Map.merge(context.attrs, %{
                code: code,
                status: "awaiting_verification",
                allocated_at: now,
                label_prepared_at: now
              })
            )
            |> Repo.insert!()

          session
          |> AggregationSession.changeset(%{
            status: "awaiting_label_verification",
            manufacturer_pallet_id: pallet.id
          })
          |> Repo.update!()

          pallet
        end)
      )
    else
      {:error, :unavailable} ->
        # GS1 may have minted the pallet label even though the response was
        # lost. Keep the session in a recoverable state and block another
        # create until the outcome has been checked.
        case session
             |> Ecto.Changeset.change(status: "reconciliation_required")
             |> Repo.update() do
          {:ok, _session} -> {:error, :reconciliation_required}
          {:error, _changeset} -> {:error, :unavailable}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def verify_pallet_parent(organization_id, session_id, raw_identifier) do
    unwrap_transaction(
      Repo.transaction(fn ->
        session = locked_session!(organization_id, session_id, "pallet")
        ensure_status!(session, "awaiting_label_verification")
        pallet = Repo.get!(Pallet, session.manufacturer_pallet_id)

        if parse_sscc!(raw_identifier) != pallet.code,
          do: Repo.rollback({:error, :parent_mismatch})

        shippers = captured_shippers(session.id)

        if Enum.any?(shippers, & &1.manufacturer_pallet_id),
          do: Repo.rollback({:error, :already_aggregated})

        now = DateTime.utc_now() |> DateTime.truncate(:second)

        Repo.update_all(from(s in ShipperSscc, where: s.id in ^Enum.map(shippers, & &1.id)),
          set: [manufacturer_pallet_id: pallet.id]
        )

        pallet
        |> Ecto.Changeset.change(
          status: "completed",
          verified_at: now,
          completed_at: now,
          trackiq_status: "pending"
        )
        |> Repo.update!()

        session
        |> AggregationSession.changeset(%{
          status: "completed",
          parent_verified_at: now,
          completed_at: now
        })
        |> Repo.update!()

        Epcis.record_manufacturer_pallet_pack(organization_id, pallet, shippers, pallet.from_gln)
        %{session_id: session.id, pallet_id: pallet.id, status: "completed"}
      end)
    )
  end

  # Retrieval ---------------------------------------------------------------

  def get_session(organization_id, session_id) do
    Repo.one(
      from s in AggregationSession,
        where: s.organization_id == ^organization_id and s.id == ^session_id,
        preload: [items: [:serial, :shipper_sscc], batch: :product, shipper_sscc: [], pallet: []]
    )
  end

  @doc """
  Operational context for a batch, shared by the web UI and mobile API.

  These are derived values only. The authoritative transitions still live in
  `prepare_shippers/3` and the session functions.
  """
  def batch_aggregation_context(organization_id, %Batch{} = batch) do
    operation = latest_generation_operation(organization_id, batch.id)
    allocated = count_batch_shippers(organization_id, batch.id)
    available = available_shipper_count(organization_id, batch.id)
    missing_prerequisites? = not shipper_request_possible?(batch)
    method = batch.shipper_preparation_method
    serials_ready? = serialization_completed?(operation)

    %{
      serialization_completed: serials_ready?,
      preparation_method: method,
      sscc_allocation_status: operation && operation.sscc_allocation_status,
      sscc_quantity: operation && operation.sscc_quantity,
      allocated_shipper_count: allocated,
      available_shipper_count: available,
      sscc_prerequisites_missing: missing_prerequisites?,
      aggregation_eligible:
        serials_ready? and method == "during_packing" and
          (available > 0 or not missing_prerequisites?)
    }
  end

  def batch_aggregation_context(organization_id, batch_id) when is_integer(batch_id) do
    batch = Repo.get_by!(Batch, id: batch_id, organization_id: organization_id)
    batch_aggregation_context(organization_id, batch)
  end

  defp serialization_completed?(nil), do: false
  defp serialization_completed?(operation), do: operation.serial_allocation_status == "completed"

  @doc "Derived session state for clients; never used to authorize a transition."
  def session_aggregation_context(organization_id, %AggregationSession{} = session) do
    expected_parent = expected_parent_sscc(organization_id, session)
    allocation_status = session_allocation_status(organization_id, session)

    %{
      capacity_reached:
        is_integer(session.expected_item_count) and
          session_item_count(session.id) >= session.expected_item_count,
      allocation_status: allocation_status,
      label_ready: expected_parent not in [nil, ""],
      expected_parent_sscc: expected_parent,
      parent_verification_pending: session.status == "awaiting_label_verification"
    }
  end

  defp expected_parent_sscc(organization_id, session) do
    parent_sscc = session.shipper_sscc && session.shipper_sscc.code
    pallet_sscc = session.pallet && session.pallet.code

    parent_sscc || pallet_sscc || awaiting_sscc_parent(organization_id, session)
  end

  defp awaiting_sscc_parent(_organization_id, %AggregationSession{status: status})
       when status != "awaiting_sscc",
       do: nil

  defp awaiting_sscc_parent(_organization_id, %AggregationSession{manufacturer_batch_id: nil}),
    do: nil

  defp awaiting_sscc_parent(organization_id, session) do
    available_shipper_code(organization_id, session.manufacturer_batch_id)
  end

  defp session_allocation_status(_organization_id, %AggregationSession{status: status})
       when status in ["awaiting_label_verification", "completed"],
       do: "completed"

  defp session_allocation_status(_organization_id, %AggregationSession{
         status: "reconciliation_required"
       }),
       do: "reconciliation_required"

  defp session_allocation_status(
         organization_id,
         %AggregationSession{status: "awaiting_sscc"} = session
       ) do
    operation =
      if is_nil(session.manufacturer_batch_id),
        do: nil,
        else: latest_generation_operation(organization_id, session.manufacturer_batch_id)

    if operation && operation.sscc_allocation_status == "reconciliation_required",
      do: "reconciliation_required",
      else: "pending"
  end

  defp session_allocation_status(_organization_id, _session), do: "not_required"

  defp serialized_exists do
    from o in GenerationOperation,
      where:
        o.manufacturer_batch_id == parent_as(:batch).id and
          o.serial_allocation_status == "completed",
      select: true
  end

  def list_active_batches(organization_id) do
    serialized = serialized_exists()

    Repo.all(
      from b in Batch,
        as: :batch,
        where:
          b.organization_id == ^organization_id and b.status in ["prepared", "aggregating"] and
            exists(serialized),
        preload: :product,
        order_by: [asc: b.inserted_at]
    )
  end

  @doc """
  Lists batches prepared for shipper aggregation or already in aggregation.

  Serialized batches that have not been prepared are intentionally excluded;
  those belong in batch inventory until they are prepared for shipper packing.
  """
  def list_shipper_aggregation_batches(organization_id) do
    serialized = serialized_exists()
    generated_counts = serial_count_for_batch()

    packed_counts =
      from s in Serial,
        where:
          s.manufacturer_batch_id == parent_as(:batch).id and
            not is_nil(s.manufacturer_shipper_sscc_id),
        select: count(s.id)

    Repo.all(
      from b in Batch,
        as: :batch,
        join: p in assoc(b, :product),
        where:
          b.organization_id == ^organization_id and
            b.shipper_preparation_method == "during_packing" and
            b.status in ["prepared", "aggregating", "completed"] and
            exists(serialized),
        order_by: [asc: b.inserted_at],
        select: %{
          batch: b,
          product: p,
          generated_count: coalesce(subquery(generated_counts), 0),
          packed_count: coalesce(subquery(packed_counts), 0)
        }
    )
  end

  defp serial_count_for_batch do
    from s in Serial,
      where: s.manufacturer_batch_id == parent_as(:batch).id,
      select: count(s.id)
  end

  def latest_generation_operation(organization_id, batch_id) do
    Repo.one(
      from o in GenerationOperation,
        where: o.organization_id == ^organization_id and o.manufacturer_batch_id == ^batch_id,
        order_by: [desc: o.id],
        limit: 1
    )
  end

  def session_summary(session_id) do
    session = Repo.get!(AggregationSession, session_id)

    %{
      id: session.id,
      session_type: session.session_type,
      status: session.status,
      expected_item_count: session.expected_item_count,
      captured_item_count: session_item_count(session.id),
      shipper_sscc_id: session.manufacturer_shipper_sscc_id,
      pallet_id: session.manufacturer_pallet_id
    }
  end

  # Internal helpers --------------------------------------------------------

  defp unwrap_transaction({:ok, value}), do: {:ok, value}
  defp unwrap_transaction({:error, {:error, reason}}), do: {:error, reason}
  defp unwrap_transaction(error), do: error

  defp rejected_gs1_note(kind, {:invalid, message}) when is_binary(message) do
    "#{gs1_label(kind)} rejected the request: #{message}"
  end

  defp rejected_gs1_note(kind, reason) do
    suffix =
      case reason do
        :unconfigured -> "the GS1 API key is not configured"
        reason when reason in [:unauthorized, :forbidden] -> "GS1 did not allow this request"
        :not_found -> "GS1 does not recognise this product"
        _other -> "the request was rejected"
      end

    "#{gs1_label(kind)} was not created: #{suffix}"
  end

  defp unexpected_response_note(kind, {:invalid, message}) when is_binary(message) do
    "#{gs1_label(kind)} response could not be used: #{message}"
  end

  defp unexpected_response_note(kind, _reason),
    do: "#{gs1_label(kind)} response could not be used"

  defp gs1_label(:serial), do: "Serials"
  defp gs1_label(:shipper), do: "Shipper SSCC"

  defp normalize_batch_attrs(attrs) do
    attrs
    |> Map.new(fn {k, v} -> {if(is_binary(k), do: String.to_existing_atom(k), else: k), v} end)
    |> Map.update!(:pack_quantity, &parse_integer!/1)
    |> Map.update!(:packs_per_shipper, &parse_integer!/1)
    |> then(fn values ->
      Map.put(
        values,
        :expected_shipper_count,
        div(values.pack_quantity, values.packs_per_shipper)
      )
    end)
  end

  defp parse_integer!(value) when is_integer(value), do: value
  defp parse_integer!(value) when is_binary(value), do: String.to_integer(value)

  defp serial_request_payload(product, batch) do
    %{
      "barcode" => product.gtin,
      "batch" => batch.batch_no,
      "production" => Date.to_iso8601(batch.production_date),
      "expiry" => Date.to_iso8601(batch.expiry_date),
      "trade_item_qty" => Integer.to_string(batch.pack_quantity),
      "create_shippers" => false
    }
  end

  # create_shipper_sscc carries the serial aggregation and needs genuine party
  # GLNs. It does not require the PO/address fields the standalone create_sscc
  # contract does, so nothing is invented for stock-oriented batches.
  defp shipper_request_possible?(batch),
    do: valid_gln?(batch.from_gln) and valid_gln?(batch.to_gln)

  defp valid_gln?(gln) when is_binary(gln), do: Regex.match?(~r/^\d{13}$/, gln)
  defp valid_gln?(_gln), do: false

  defp serial_values(%{"primary_datamatrices" => values}) when is_list(values) do
    serials = Enum.map(values, &Map.get(&1, "serial"))

    {:ok, serials |> Enum.reject(&is_nil/1) |> Enum.uniq()}
  end

  defp serial_values(_), do: {:error, :missing_serials}

  defp persist_serials!(operation, values) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(
        values,
        &%{
          organization_id: operation.organization_id,
          manufacturer_product_id: operation.manufacturer_product_id,
          manufacturer_batch_id: operation.manufacturer_batch_id,
          serial: &1,
          inserted_at: now,
          updated_at: now
        }
      )

    Repo.insert_all(Serial, rows, on_conflict: :nothing)

    Repo.all(
      from s in Serial,
        where: s.manufacturer_batch_id == ^operation.manufacturer_batch_id and s.serial in ^values
    )
  end

  defp persist_available_shipper!(operation, code, payload) do
    batch = operation.batch
    product = operation.product
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    serials = Map.get(payload, "serials", [])

    shipper =
      %ShipperSscc{organization_id: operation.organization_id}
      |> ShipperSscc.changeset(%{
        code: code,
        gtin: product.gtin,
        batch: batch.batch_no,
        production_date: batch.production_date,
        expiry_date: batch.expiry_date,
        count_of_trade_items: length(serials),
        packed_serials: serials,
        from_gln: batch.from_gln,
        from_company_name: batch.from_company_name,
        from_address: batch.from_address,
        to_gln: batch.to_gln,
        to_company_name: batch.to_company_name,
        to_address: batch.to_address,
        order_number: batch.order_number,
        status: "available",
        allocated_at: now
      })
      |> Repo.insert!()

    %SsccBatch{}
    |> SsccBatch.changeset(%{
      manufacturer_shipper_sscc_id: shipper.id,
      manufacturer_batch_id: batch.id
    })
    |> Repo.insert!()

    shipper
  end

  defp count_batch_shippers(organization_id, batch_id),
    do:
      Repo.aggregate(
        from(s in ShipperSscc,
          join: sb in SsccBatch,
          on: sb.manufacturer_shipper_sscc_id == s.id,
          where: s.organization_id == ^organization_id and sb.manufacturer_batch_id == ^batch_id
        ),
        :count
      )

  defp available_shipper_count(organization_id, batch_id),
    do:
      Repo.aggregate(
        from(s in ShipperSscc,
          join: sb in SsccBatch,
          on: sb.manufacturer_shipper_sscc_id == s.id,
          where:
            s.organization_id == ^organization_id and sb.manufacturer_batch_id == ^batch_id and
              s.status == "available"
        ),
        :count
      )

  defp available_shipper!(organization_id, batch_id),
    do:
      Repo.one!(
        from s in ShipperSscc,
          join: sb in SsccBatch,
          on: sb.manufacturer_shipper_sscc_id == s.id,
          where:
            s.organization_id == ^organization_id and sb.manufacturer_batch_id == ^batch_id and
              s.status == "available",
          order_by: [asc: s.id],
          limit: 1,
          lock: "FOR UPDATE"
      )

  defp available_shipper_code(organization_id, batch_id),
    do:
      Repo.one(
        from s in ShipperSscc,
          join: sb in SsccBatch,
          on: sb.manufacturer_shipper_sscc_id == s.id,
          where:
            s.organization_id == ^organization_id and sb.manufacturer_batch_id == ^batch_id and
              s.status == "available",
          order_by: [asc: s.id],
          limit: 1,
          select: s.code
      )

  defp latest_generation_operation!(organization_id, batch_id),
    do:
      Repo.one!(
        from o in GenerationOperation,
          where: o.organization_id == ^organization_id and o.manufacturer_batch_id == ^batch_id,
          order_by: [desc: o.id],
          limit: 1,
          lock: "FOR UPDATE"
      )

  defp ensure_serialization_completed!(organization_id, batch_id) do
    if Repo.exists?(
         from o in GenerationOperation,
           where:
             o.organization_id == ^organization_id and o.manufacturer_batch_id == ^batch_id and
               o.serial_allocation_status == "completed"
       ),
       do: :ok,
       else: Repo.rollback({:error, :serialization_not_completed})
  end

  defp ensure_batch_ready!(%Batch{status: status}) when status in ["prepared", "aggregating"],
    do: :ok

  defp ensure_batch_ready!(_), do: Repo.rollback({:error, :batch_not_ready})

  defp ensure_preparation_selected!("during_packing"), do: :ok

  defp ensure_preparation_selected!(_),
    do: Repo.rollback({:error, :shipper_preparation_required})

  defp ensure_status!(%AggregationSession{status: status}, expected) when status == expected,
    do: :ok

  defp ensure_status!(_, _), do: Repo.rollback({:error, :invalid_session_stage})

  defp ensure_no_active_session!(organization_id, type, batch_id) do
    query =
      from s in AggregationSession,
        where:
          s.organization_id == ^organization_id and s.session_type == ^type and
            s.status in ^@active_session_statuses

    query =
      if is_nil(batch_id),
        do: query,
        else: where(query, [s], s.manufacturer_batch_id == ^batch_id)

    if Repo.exists?(query), do: Repo.rollback({:error, :active_session_exists}), else: :ok
  end

  defp locked_session!(organization_id, session_id, type),
    do:
      Repo.one!(
        from s in AggregationSession,
          where:
            s.id == ^session_id and s.organization_id == ^organization_id and
              s.session_type == ^type,
          lock: "FOR UPDATE"
      )

  defp session_items!(id, kind),
    do:
      Repo.all(
        from i in AggregationSessionItem,
          where:
            i.manufacturer_aggregation_session_id == ^id and
              not is_nil(
                field(
                  i,
                  ^if(kind == :serial,
                    do: :manufacturer_serial_id,
                    else: :manufacturer_shipper_sscc_id
                  )
                )
              )
      )

  defp session_item_count(id),
    do:
      Repo.aggregate(
        from(i in AggregationSessionItem, where: i.manufacturer_aggregation_session_id == ^id),
        :count
      )

  defp advance_shipper_when_full!(session) do
    count = session_item_count(session.id)
    if count > session.expected_item_count, do: Repo.rollback({:error, :capacity_reached})

    if count == session.expected_item_count do
      session
      |> AggregationSession.changeset(%{status: "awaiting_sscc"})
      |> Repo.update!()

      session_summary(session.id)
    else
      session_summary(session.id)
    end
  end

  defp parse_product_identifier!(raw) do
    case GS1Decoder.parse(raw) do
      {:ok, %{gtin: gtin, serial: serial} = identifier}
      when not is_nil(gtin) and not is_nil(serial) ->
        identifier

      _ ->
        Repo.rollback({:error, :invalid_product_identifier})
    end
  end

  defp ensure_product_identifier!(identifier, batch) do
    product = batch.product

    if normalize_gtin(identifier.gtin) != normalize_gtin(product.gtin) or
         (identifier.batch_no && identifier.batch_no != batch.batch_no),
       do: Repo.rollback({:error, :wrong_product_or_batch})
  end

  defp normalize_gtin(gtin), do: gtin |> to_string() |> String.pad_leading(14, "0")

  defp parse_sscc!(raw) do
    case GS1Decoder.parse(raw) do
      {:ok, %{sscc: sscc}} when is_binary(sscc) ->
        sscc

      _ ->
        value = raw |> to_string() |> String.trim()

        if Regex.match?(~r/^\d{18}$/, value),
          do: value,
          else: Repo.rollback({:error, :invalid_sscc})
    end
  end

  defp scan_error(changeset) do
    duplicate? =
      Keyword.has_key?(changeset.errors, :manufacturer_serial_id) or
        Keyword.has_key?(changeset.errors, :manufacturer_shipper_sscc_id)

    if duplicate?, do: {:error, :duplicate_scan}, else: {:error, :invalid_scan}
  end

  defp ensure_pallet_eligible!(session, shipper) do
    cond do
      shipper.status == "in_transit" ->
        Repo.rollback({:error, :shipper_in_transit})

      shipper.status != "completed" ->
        Repo.rollback({:error, :shipper_not_completed})

      shipper.manufacturer_pallet_id ->
        Repo.rollback({:error, :already_aggregated})

      destination_conflict?(session.id, shipper) ->
        Repo.rollback({:error, :different_destination})

      true ->
        :ok
    end
  end

  defp destination_conflict?(session_id, shipper) do
    existing = captured_shippers(session_id)

    case existing do
      [] -> false
      [first | _] -> blank(first.to_gln) != blank(shipper.to_gln)
    end
  end

  defp blank(value) when value in [nil, ""], do: nil
  defp blank(value), do: value

  defp captured_shippers(session_id),
    do:
      Repo.all(
        from s in ShipperSscc,
          join: i in AggregationSessionItem,
          on: i.manufacturer_shipper_sscc_id == s.id,
          where: i.manufacturer_aggregation_session_id == ^session_id,
          order_by: [asc: i.id]
      )

  defp pallet_context([first | _] = shippers) do
    batches =
      shippers
      |> Enum.flat_map(fn shipper ->
        Repo.all(
          from b in Batch,
            join: sb in SsccBatch,
            on: sb.manufacturer_batch_id == b.id,
            where: sb.manufacturer_shipper_sscc_id == ^shipper.id
        )
      end)
      |> Enum.uniq_by(& &1.id)

    product_names =
      batches
      |> Enum.map(&Repo.get!(Product, &1.manufacturer_product_id).name)
      |> Enum.uniq()
      |> Enum.join(", ")

    attrs = %{
      from_gln: first.from_gln,
      from_company_name: first.from_company_name,
      from_address: first.from_address,
      to_gln: first.to_gln,
      to_company_name: first.to_company_name,
      to_address: first.to_address
    }

    params = %{
      "batch_info" =>
        Enum.map(
          batches,
          &%{
            "batch" => &1.batch_no,
            "production_date" => Date.to_iso8601(&1.production_date),
            "expiry_date" => Date.to_iso8601(&1.expiry_date)
          }
        ),
      "address" => %{
        "from_address" => first.from_address || first.from_gln,
        "to_address" => first.to_address
      },
      "count_of_trade_items" => Integer.to_string(length(shippers)),
      "material_description" => product_names,
      "order_number" => first.order_number,
      "facility_gln" => first.from_gln
    }

    if first.order_number in [nil, ""] or first.to_address in [nil, ""],
      do: {:error, {:invalid, "GS1 create_sscc requires a PO and destination address"}},
      else: {:ok, %{attrs: attrs, params: params}}
  end
end
