defmodule ThamaniDawa.Manufacturing.OperationsTest do
  use ThamaniDawa.DataCase, async: false

  import ThamaniDawa.ManufacturerFixtures

  alias ThamaniDawa.GS1.MemberApiStub
  alias ThamaniDawa.Manufacturing.AggregationSessionItem
  alias ThamaniDawa.Manufacturing.Operations
  alias ThamaniDawa.Manufacturing.Pallet
  alias ThamaniDawa.Manufacturing.Serial
  alias ThamaniDawa.Manufacturing.ShipperSscc
  alias ThamaniDawa.Manufacturing.SsccBatch
  alias ThamaniDawa.Repo

  @gs <<29>>
  @destination_gln "0614141000784"

  setup do
    MemberApiStub.reset()

    organization = manufacturer_organization_fixture()
    site = manufacturing_site_fixture(organization.id)
    user = manufacturer_user_fixture(%{organization_id: organization.id, site_id: site.id})
    product = manufacturer_product_fixture(organization.id)

    %{
      organization: organization,
      site: site,
      user: user,
      product: product
    }
  end

  describe "serialization" do
    test "creates only serials and never requests an SSCC", ctx do
      %{organization: organization, site: site, product: product} = ctx
      attrs = batch_attrs(site)
      assert %{batch: batch, operation: operation} = prepare(product, attrs)

      assert operation.serial_request_payload["create_shippers"] == false
      refute Map.has_key?(operation.serial_request_payload, "order_number")
      assert operation.sscc_quantity == 0
      assert operation.sscc_allocation_status == "not_required"
      assert MemberApiStub.serial_requests() == []
      assert MemberApiStub.create_requests() == []

      assert {:ok, completed} = Operations.allocate_identifiers(operation.id)
      assert completed.status == "completed"
      assert completed.serial_allocation_status == "completed"
      assert completed.sscc_allocation_status == "not_required"

      assert serial_values(organization.id, batch.id) == ["0001", "0002", "0003", "0004"]
      assert batch_shipper_count(organization.id, batch.id) == 0
      assert MemberApiStub.create_requests() == []

      [request] = MemberApiStub.serial_requests()
      assert request["barcode"] == product.gtin
      assert request["batch"] == batch.batch_no
      assert request["trade_item_qty"] == "4"
      assert request["create_shippers"] == false

      context = Operations.batch_aggregation_context(organization.id, batch.id)
      assert context.serialization_completed
      assert context.sscc_prerequisites_missing
      refute context.aggregation_eligible
    end

    test "bulk-allocates 10,000 serials through one GS1 request", ctx do
      %{organization: organization, site: site, product: product} = ctx
      quantity = 10_000

      assert %{batch: batch, operation: operation} =
               prepare(
                 product,
                 batch_attrs(site, %{"pack_quantity" => Integer.to_string(quantity)})
               )

      assert operation.serial_quantity == quantity

      assert {:ok, completed} = Operations.allocate_identifiers(operation.id)
      assert completed.status == "completed"
      assert completed.serial_allocation_status == "completed"

      values = serial_values(organization.id, batch.id)
      assert length(values) == quantity
      assert Enum.uniq(values) == values

      [request] = MemberApiStub.serial_requests()
      assert request["trade_item_qty"] == Integer.to_string(quantity)
      assert request["create_shippers"] == false
      assert MemberApiStub.create_requests() == []
    end

    test "retains genuine order metadata without allocating shipper identifiers", ctx do
      %{site: site, product: product} = ctx
      order = order_attrs()
      %{batch: batch, operation: operation} = prepare(product, batch_attrs(site, order))

      assert {:ok, _completed} = Operations.allocate_identifiers(operation.id)

      assert batch.order_number == order["order_number"]
      assert batch.to_gln == order["to_gln"]
      assert batch.to_company_name == order["to_company_name"]
      assert batch.to_address == order["to_address"]
      assert batch.from_company_name == "Test Origin Company"
      assert batch.from_address == "Test Origin Address"
      assert batch_shipper_count(ctx.organization.id, batch.id) == 0
      assert MemberApiStub.create_requests() == []

      context = Operations.batch_aggregation_context(ctx.organization.id, batch.id)
      assert context.serialization_completed
      refute context.sscc_prerequisites_missing
    end
  end

  describe "shipper preparation" do
    test "marks a batch prepared without allocating an SSCC or queueing another job", ctx do
      %{organization: organization, site: site, product: product} = ctx
      attrs = batch_attrs(site, order_attrs())

      assert %{batch: batch, operation: operation} = prepare(product, attrs)
      assert {:ok, serial_job} = Operations.enqueue_generation(operation)
      assert {:ok, _completed} = Operations.allocate_identifiers(operation.id)

      assert {:ok, %{batch: prepared, operation: operation}} =
               Operations.prepare_shippers(organization.id, batch.id, "during_packing")

      assert prepared.status == "prepared"
      assert prepared.shipper_preparation_method == "during_packing"
      assert operation.sscc_quantity == 0
      assert operation.sscc_allocation_status == "not_required"
      assert MemberApiStub.create_requests() == []
      assert MemberApiStub.shipper_sscc_requests() == []

      jobs =
        Oban.Job
        |> Repo.all()
        |> Enum.filter(
          &(&1.worker == "ThamaniDawa.Manufacturing.IdentifierAllocationWorker" and
              &1.args["operation_id"] == operation.id)
        )

      assert Enum.map(jobs, & &1.id) == [serial_job.id]
    end

    test "rejects the removed before-packing mode without touching identifiers", ctx do
      %{organization: organization, site: site, product: product} = ctx
      batch = serialized_batch(product, batch_attrs(site, order_attrs()))

      assert {:error, :unsupported_preparation_method} =
               Operations.prepare_shippers(organization.id, batch.id, "before_packing")

      assert MemberApiStub.create_requests() == []
      assert MemberApiStub.shipper_sscc_requests() == []

      assert is_nil(
               Repo.get!(ThamaniDawa.Manufacturing.Batch, batch.id).shipper_preparation_method
             )
    end

    test "requires a destination GLN before a stock batch starts packing", ctx do
      %{organization: organization, user: user, site: site, product: product} = ctx
      batch = serialized_batch(product, batch_attrs(site))

      assert {:ok, %{batch: prepared, operation: operation}} =
               Operations.prepare_shippers(organization.id, batch.id, "during_packing")

      assert prepared.shipper_preparation_method == "during_packing"
      assert operation.sscc_quantity == 0
      assert operation.sscc_allocation_status == "not_required"
      assert MemberApiStub.create_requests() == []

      assert {:error, :sscc_prerequisites_missing} =
               Operations.start_shipper_session(organization.id, user.id, batch.id)
    end
  end

  describe "during-packing shipper session" do
    test "validates scans, allocates one SSCC, and verifies the applied parent", ctx do
      %{organization: organization, user: user, site: site, product: product} = ctx
      batch = serialized_batch(product, batch_attrs(site, order_attrs()))
      assert {:ok, _} = Operations.prepare_shippers(organization.id, batch.id, "during_packing")
      assert {:ok, session} = Operations.start_shipper_session(organization.id, user.id, batch.id)

      assert session.status == "scanning"
      assert is_nil(session.manufacturer_shipper_sscc_id)
      assert batch_shipper_count(organization.id, batch.id) == 0

      first_payload = serial_payload(product, batch, "0001")

      assert {:ok, _} =
               Operations.capture_product_scan(organization.id, session.id, first_payload)

      assert {:error, :duplicate_scan} =
               Operations.capture_product_scan(organization.id, session.id, first_payload)

      assert {:error, :wrong_product_or_batch} =
               Operations.capture_product_scan(
                 organization.id,
                 session.id,
                 "01" <> product.gtin <> "10OTHER-BATCH" <> @gs <> "21" <> "0002"
               )

      assert {:error, :unknown_serial} =
               Operations.capture_product_scan(
                 organization.id,
                 session.id,
                 serial_payload(product, batch, "9999")
               )

      assert Operations.get_session(organization.id, session.id).status == "scanning"
      assert session_captured_count(session.id) == 1

      assert {:ok, _} =
               Operations.capture_product_scan(
                 organization.id,
                 session.id,
                 serial_payload(product, batch, "0002")
               )

      assert Operations.get_session(organization.id, session.id).status == "awaiting_sscc"
      assert batch_shipper_count(organization.id, batch.id) == 0
      assert MemberApiStub.create_requests() == []

      assert {:ok, %{allocation: :pending}} =
               Operations.request_shipper_sscc(organization.id, session.id)

      assert MemberApiStub.create_requests() == []

      operation = Operations.latest_generation_operation(organization.id, batch.id)
      assert operation.sscc_quantity == 1
      assert operation.sscc_allocation_status == "pending"
      assert operation.sscc_request_payload["barcode"] == product.gtin
      assert operation.sscc_request_payload["serials"] == ["0001", "0002"]
      assert operation.sscc_request_payload["from"]["gln"] == site.gln
      assert operation.sscc_request_payload["to"]["gln"] == @destination_gln

      # A repeated request must not queue a second non-idempotent create call.
      assert {:ok, %{allocation: :pending}} =
               Operations.request_shipper_sscc(organization.id, session.id)

      jobs =
        Oban.Job
        |> Repo.all()
        |> Enum.filter(
          &(&1.worker == "ThamaniDawa.Manufacturing.IdentifierAllocationWorker" and
              &1.args["operation_id"] == operation.id)
        )

      assert length(jobs) == 1

      assert {:ok, _} = Operations.allocate_identifiers(operation.id)

      [request] = MemberApiStub.shipper_sscc_requests()
      assert request["barcode"] == product.gtin
      assert request["serials"] == ["0001", "0002"]
      assert MemberApiStub.create_requests() == []

      [shipper] = batch_shippers(organization.id, batch.id)
      assert shipper.status == "available"
      assert shipper.count_of_trade_items == 2
      assert MapSet.new(shipper.packed_serials) == MapSet.new(["0001", "0002"])

      assert {:ok, assigned} = Operations.assign_shipper_sscc(organization.id, session.id)
      assert assigned.status == "awaiting_label_verification"
      assert assigned.manufacturer_shipper_sscc_id == shipper.id

      context = Operations.session_aggregation_context(organization.id, assigned)
      assert context.capacity_reached
      assert context.allocation_status == "completed"
      assert context.label_ready
      assert context.expected_parent_sscc == shipper.code
      assert context.parent_verification_pending

      assert {:error, :parent_mismatch} =
               Operations.verify_shipper_parent(organization.id, session.id, wrong_sscc())

      assert Repo.get!(ShipperSscc, shipper.id).status == "awaiting_verification"

      assert {:ok, result} =
               Operations.verify_shipper_parent(organization.id, session.id, shipper.code)

      assert result.status == "completed"
      assert Operations.get_session(organization.id, session.id).status == "completed"

      completed = Repo.get!(ShipperSscc, shipper.id)
      assert completed.status == "completed"
      assert completed.count_of_trade_items == 2
      assert MapSet.new(completed.packed_serials) == MapSet.new(["0001", "0002"])
      assert completed.trackiq_status == "pending"

      assert serial_values(organization.id, batch.id, assigned_shipper_id: shipper.id) ==
               ["0001", "0002"]
    end

    test "each shipper is created with only the serials scanned for that carton", ctx do
      %{organization: organization, user: user, site: site, product: product} = ctx
      batch = serialized_batch(product, batch_attrs(site, order_attrs()))
      assert {:ok, _} = Operations.prepare_shippers(organization.id, batch.id, "during_packing")

      assert {:ok, first_session} =
               Operations.start_shipper_session(organization.id, user.id, batch.id)

      for serial <- ["0001", "0002"] do
        assert {:ok, _} =
                 Operations.capture_product_scan(
                   organization.id,
                   first_session.id,
                   serial_payload(product, batch, serial)
                 )
      end

      assert {:ok, %{allocation: :pending}} =
               Operations.request_shipper_sscc(organization.id, first_session.id)

      first_operation = Operations.latest_generation_operation(organization.id, batch.id)
      assert {:ok, _} = Operations.allocate_identifiers(first_operation.id)

      assert {:ok, first_assigned} =
               Operations.assign_shipper_sscc(organization.id, first_session.id)

      assert {:ok, first_result} =
               Operations.verify_shipper_parent(
                 organization.id,
                 first_session.id,
                 first_assigned.shipper_sscc.code
               )

      assert first_result.status == "completed"

      assert {:ok, second_session} =
               Operations.start_shipper_session(organization.id, user.id, batch.id)

      for serial <- ["0003", "0004"] do
        assert {:ok, _} =
                 Operations.capture_product_scan(
                   organization.id,
                   second_session.id,
                   serial_payload(product, batch, serial)
                 )
      end

      assert {:ok, %{allocation: :pending}} =
               Operations.request_shipper_sscc(organization.id, second_session.id)

      second_operation = Operations.latest_generation_operation(organization.id, batch.id)
      assert second_operation.sscc_request_payload["serials"] == ["0003", "0004"]
      assert {:ok, _} = Operations.allocate_identifiers(second_operation.id)

      requests = MemberApiStub.shipper_sscc_requests()
      assert length(requests) == 2
      assert Enum.map(requests, & &1["serials"]) == [["0001", "0002"], ["0003", "0004"]]
      assert MemberApiStub.create_requests() == []

      shippers = batch_shippers(organization.id, batch.id)
      assert length(shippers) == 2

      assert MapSet.new(Enum.flat_map(shippers, & &1.packed_serials)) ==
               MapSet.new(["0001", "0002", "0003", "0004"])
    end

    test "an uncertain shipper create is reconciled rather than blindly retried", ctx do
      %{organization: organization, user: user, site: site, product: product} = ctx
      batch = serialized_batch(product, batch_attrs(site, order_attrs()))
      assert {:ok, _} = Operations.prepare_shippers(organization.id, batch.id, "during_packing")
      assert {:ok, session} = Operations.start_shipper_session(organization.id, user.id, batch.id)

      for serial <- ["0001", "0002"] do
        assert {:ok, _} =
                 Operations.capture_product_scan(
                   organization.id,
                   session.id,
                   serial_payload(product, batch, serial)
                 )
      end

      assert {:ok, %{allocation: :pending}} =
               Operations.request_shipper_sscc(organization.id, session.id)

      operation = Operations.latest_generation_operation(organization.id, batch.id)
      MemberApiStub.fail_next(:unavailable)

      assert {:ok, uncertain} = Operations.allocate_identifiers(operation.id)
      assert uncertain.status == "reconciliation_required"
      assert uncertain.sscc_allocation_status == "reconciliation_required"
      assert uncertain.reconciliation_note =~ "couldn't confirm whether GS1 created"
      assert batch_shipper_count(organization.id, batch.id) == 0

      assert {:error, :not_actionable} = Operations.allocate_identifiers(operation.id)
      assert length(MemberApiStub.shipper_sscc_requests()) == 1
      assert batch_shipper_count(organization.id, batch.id) == 0
    end
  end

  describe "pallet session" do
    test "rejects invalid parents, allocates one pallet SSCC, and verifies the hierarchy", ctx do
      %{organization: organization, user: user, site: site, product: product} = ctx
      batch = serialized_batch(product, batch_attrs(site, order_attrs()))
      shipper = completed_shipper(ctx, batch)

      assert {:ok, session} = Operations.start_pallet_session(organization.id, user.id)

      assert {:ok, _} = Operations.capture_shipper_scan(organization.id, session.id, shipper.code)

      assert {:error, :duplicate_scan} =
               Operations.capture_shipper_scan(organization.id, session.id, shipper.code)

      in_transit = completed_shipper(ctx, batch, status: "in_transit")

      assert {:error, :shipper_in_transit} =
               Operations.capture_shipper_scan(organization.id, session.id, in_transit.code)

      different_destination =
        completed_shipper(ctx, batch,
          to_gln: "0614141000456",
          to_address: "Test Other Destination"
        )

      assert {:error, :different_destination} =
               Operations.capture_shipper_scan(
                 organization.id,
                 session.id,
                 different_destination.code
               )

      assert {:ok, _} = Operations.finish_pallet_loading(organization.id, session.id)
      assert Operations.get_session(organization.id, session.id).status == "awaiting_sscc"

      assert {:ok, %Pallet{code: pallet_code}} =
               Operations.allocate_pallet_sscc(organization.id, session.id)

      pallet = Operations.get_session(organization.id, session.id).pallet
      assert pallet.code == pallet_code
      assert pallet.to_gln == shipper.to_gln
      assert pallet.from_gln == site.gln

      assert {:error, :parent_mismatch} =
               Operations.verify_pallet_parent(organization.id, session.id, wrong_sscc())

      assert {:ok, result} =
               Operations.verify_pallet_parent(organization.id, session.id, pallet.code)

      assert result.status == "completed"
      assert Repo.get!(ShipperSscc, shipper.id).manufacturer_pallet_id == pallet.id
      assert Repo.get!(Pallet, pallet.id).status == "completed"
    end

    test "holds a pallet for reconciliation when the GS1 outcome is unknown", ctx do
      %{organization: organization, user: user, site: site, product: product} = ctx
      batch = serialized_batch(product, batch_attrs(site, order_attrs()))
      shipper = completed_shipper(ctx, batch)

      assert {:ok, session} = Operations.start_pallet_session(organization.id, user.id)
      assert {:ok, _} = Operations.capture_shipper_scan(organization.id, session.id, shipper.code)
      assert {:ok, _} = Operations.finish_pallet_loading(organization.id, session.id)

      MemberApiStub.fail_next(:unavailable)

      assert {:error, :reconciliation_required} =
               Operations.allocate_pallet_sscc(organization.id, session.id)

      assert Operations.get_session(organization.id, session.id).status ==
               "reconciliation_required"

      assert {:error, :not_actionable} =
               Operations.allocate_pallet_sscc(organization.id, session.id)
    end
  end

  describe "uncertain serial allocation" do
    test "imports serials GS1 confirms were created for the batch", ctx do
      %{organization: organization, site: site, product: product} = ctx
      %{batch: batch, operation: operation} = prepare(product, batch_attrs(site))

      # GS1 minted the serials but the response never reached us.
      MemberApiStub.post_create_serials(%{
        "barcode" => product.gtin,
        "batch" => batch.batch_no,
        "trade_item_qty" => "4",
        "create_shippers" => false
      })

      MemberApiStub.fail_next(:unavailable)

      assert {:ok, uncertain} = Operations.allocate_identifiers(operation.id)
      assert uncertain.serial_allocation_status == "reconciliation_required"
      assert serial_values(organization.id, batch.id) == []

      assert {:ok, %{result: :recovered, operation: recovered}} =
               Operations.reconcile_serial_allocation(operation.id)

      assert recovered.serial_allocation_status == "completed"
      assert serial_values(organization.id, batch.id) == ["0001", "0002", "0003", "0004"]
    end

    test "retries the same intent when GS1 confirms no serials exist", ctx do
      %{organization: organization, site: site, product: product} = ctx
      %{batch: batch, operation: operation} = prepare(product, batch_attrs(site))

      MemberApiStub.fail_next(:unavailable)
      assert {:ok, _uncertain} = Operations.allocate_identifiers(operation.id)
      MemberApiStub.clear_serial_creates()

      assert {:ok, %{result: :retry_scheduled}} =
               Operations.reconcile_serial_allocation(operation.id)

      assert Repo.reload!(operation).serial_allocation_status == "pending"

      assert {:ok, retried} = Operations.allocate_identifiers(operation.id)
      assert retried.serial_allocation_status == "completed"
      assert serial_values(organization.id, batch.id) == ["0001", "0002", "0003", "0004"]
    end

    test "reports a flat error when shippers cannot be prepared yet", ctx do
      %{organization: organization, site: site, product: product} = ctx
      %{batch: batch, operation: operation} = prepare(product, batch_attrs(site))

      assert {:error, :serialization_not_completed} =
               Operations.prepare_shippers(organization.id, batch.id, "during_packing")

      assert {:ok, _completed} = Operations.allocate_identifiers(operation.id)

      assert {:ok, _prepared} =
               Operations.prepare_shippers(organization.id, batch.id, "during_packing")
    end
  end

  defp prepare(product, attrs) do
    {:ok, result} = Operations.prepare_generation(product.organization_id, product.id, attrs)
    result
  end

  defp serialized_batch(product, attrs) do
    %{batch: batch, operation: operation} = prepare(product, attrs)
    assert {:ok, _completed} = Operations.allocate_identifiers(operation.id)
    Repo.preload(batch, :product)
  end

  defp batch_attrs(site, overrides \\ %{}) do
    %{
      "batch_no" => "TEST-B#{System.unique_integer([:positive])}",
      "production_date" => "2026-01-05",
      "expiry_date" => "2027-01-05",
      "pack_quantity" => "4",
      "packs_per_shipper" => "2",
      "from_gln" => site.gln,
      "from_company_name" => "Test Origin Company",
      "from_address" => "Test Origin Address"
    }
    |> Map.merge(overrides)
  end

  defp order_attrs do
    %{
      "order_number" => "TEST-PO-#{System.unique_integer([:positive])}",
      "to_gln" => @destination_gln,
      "to_company_name" => "Afya Test Org",
      "to_address" => "Nairobi, Kenya"
    }
  end

  defp serial_payload(product, batch, serial) do
    "01" <> product.gtin <> "10" <> batch.batch_no <> @gs <> "21" <> serial
  end

  defp wrong_sscc do
    unique = System.unique_integer([:positive])
    padded = String.pad_leading(Integer.to_string(unique), 9, "0")
    body = "06160000" <> padded

    body <> Integer.to_string(ThamaniDawa.GS1.Sscc.mod10_check_digit(body))
  end

  defp completed_shipper(%{organization: organization} = ctx, batch, overrides \\ []) do
    attrs =
      %{
        organization_id: organization.id,
        code: wrong_sscc(),
        gtin: ctx.product.gtin,
        batch: batch.batch_no,
        from_gln: batch.from_gln,
        from_company_name: batch.from_company_name,
        from_address: batch.from_address,
        to_gln: batch.to_gln,
        to_company_name: batch.to_company_name,
        to_address: batch.to_address,
        order_number: batch.order_number,
        status: "completed"
      }
      |> Map.merge(Map.new(overrides))

    shipper = Repo.insert!(struct(ShipperSscc, attrs))

    Repo.insert!(%SsccBatch{
      manufacturer_shipper_sscc_id: shipper.id,
      manufacturer_batch_id: batch.id
    })

    shipper
  end

  defp batch_shippers(organization_id, batch_id) do
    Repo.all(
      from s in ShipperSscc,
        join: sb in SsccBatch,
        on: sb.manufacturer_shipper_sscc_id == s.id,
        where: s.organization_id == ^organization_id and sb.manufacturer_batch_id == ^batch_id,
        order_by: [asc: s.id]
    )
  end

  defp batch_shipper_count(organization_id, batch_id),
    do: length(batch_shippers(organization_id, batch_id))

  defp serial_values(organization_id, batch_id, opts \\ []) do
    query =
      from s in Serial,
        where: s.organization_id == ^organization_id and s.manufacturer_batch_id == ^batch_id,
        order_by: [asc: s.serial]

    query =
      case Keyword.get(opts, :assigned_shipper_id) do
        nil -> where(query, [s], is_nil(s.manufacturer_shipper_sscc_id))
        id -> where(query, [s], s.manufacturer_shipper_sscc_id == ^id)
      end

    serials = Repo.all(query)
    Enum.map(serials, & &1.serial)
  end

  defp session_captured_count(session_id) do
    query =
      from i in AggregationSessionItem,
        where: i.manufacturer_aggregation_session_id == ^session_id

    Repo.aggregate(query, :count)
  end
end
