defmodule ThamaniDawaWeb.Api.V1.ManufacturerAggregationControllerTest do
  use ThamaniDawaWeb.ConnCase, async: false

  import Ecto.Query
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.ManufacturerFixtures

  alias ThamaniDawa.GS1.MemberApiStub
  alias ThamaniDawa.Manufacturing.Operations
  alias ThamaniDawa.Manufacturing.{Serial, ShipperSscc, SsccBatch}
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites

  # GS1 sandbox directory row exposed by MemberApiStub. Never a live destination.
  @destination_gln "0614141000784"

  setup do
    MemberApiStub.reset()
    :ok
  end

  describe "GET /api/v1/manufacturer/aggregation/batches" do
    test "serialized stock batch reports completed serialization with no SSCC prerequisites or identifiers",
         %{
           conn: conn
         } do
      ctx = serialized_batch_context(conn)
      conn = ctx.conn

      assert Repo.aggregate(
               from(s in ShipperSscc, where: s.organization_id == ^ctx.org_id),
               :count
             ) == 0

      assert MemberApiStub.create_requests() == []

      conn = get(conn, ~p"/api/v1/manufacturer/aggregation/batches")
      batches = json_response(conn, 200)["data"]["batches"]
      payload = Enum.find(batches, &(&1["id"] == ctx.batch.id))

      assert payload
      assert payload["batch_no"] == ctx.batch.batch_no
      assert payload["status"] == "prepared"
      assert payload["pack_quantity"] == 4
      assert payload["packs_per_shipper"] == 2
      assert payload["expected_shipper_count"] == 2
      assert payload["preparation_method"] == nil
      assert payload["serialization_completed"] == true
      assert payload["sscc_allocation_status"] == "not_required"
      assert payload["sscc_quantity"] == 0
      assert payload["allocated_shipper_count"] == 0
      assert payload["available_shipper_count"] == 0
      assert payload["sscc_prerequisites_missing"] == true
      assert payload["aggregation_eligible"] == false
      assert payload["from_gln"] == ctx.site.gln
      assert payload["order_number"] == nil
      assert payload["to_gln"] == nil
      assert payload["product"]["id"] == ctx.product.id
      assert payload["product"]["gtin"] == ctx.product.gtin

      for field <- ~w(preparation_method serialization_completed sscc_allocation_status
                      sscc_quantity allocated_shipper_count available_shipper_count
                      sscc_prerequisites_missing aggregation_eligible from_gln) do
        assert Map.has_key?(payload, field), "missing batch field #{field}"
      end
    end
  end

  describe "POST /api/v1/manufacturer/aggregation/batches/:batch_id/prepare" do
    test "during_packing records the choice for a stock batch without allocating an SSCC", %{
      conn: conn
    } do
      ctx = serialized_batch_context(conn)

      conn =
        post_keyed(
          ctx.conn,
          ~p"/api/v1/manufacturer/aggregation/batches/#{ctx.batch.id}/prepare",
          %{method: "during_packing"}
        )

      data = json_response(conn, 200)["data"]
      payload = data["batch"]

      assert payload["id"] == ctx.batch.id
      assert payload["preparation_method"] == "during_packing"
      assert payload["serialization_completed"] == true
      assert payload["sscc_allocation_status"] == "not_required"
      assert payload["sscc_quantity"] == 0
      assert payload["allocated_shipper_count"] == 0
      assert payload["available_shipper_count"] == 0
      assert payload["sscc_prerequisites_missing"] == true
      assert payload["aggregation_eligible"] == false
      assert payload["from_gln"] == ctx.site.gln
      assert data["sscc_allocation_status"] == "not_required"
      assert data["sscc_quantity"] == 0

      assert Repo.get!(ThamaniDawa.Manufacturing.Batch, ctx.batch.id).shipper_preparation_method ==
               "during_packing"

      assert Repo.aggregate(
               from(s in ShipperSscc, where: s.organization_id == ^ctx.org_id),
               :count
             ) == 0

      assert MemberApiStub.create_requests() == []
    end

    test "the removed before-packing mode is rejected without any GS1 call", %{conn: conn} do
      ctx = serialized_batch_context(conn, order?: true)

      conn =
        post_keyed(
          ctx.conn,
          ~p"/api/v1/manufacturer/aggregation/batches/#{ctx.batch.id}/prepare",
          %{method: "before_packing"}
        )

      error = json_response(conn, 422)["error"]
      assert error["code"] == "unsupported_preparation_method"
      assert error["message"] =~ "prepared during packing"
      assert MemberApiStub.create_requests() == []
      assert MemberApiStub.shipper_sscc_requests() == []

      assert Repo.aggregate(
               from(s in ShipperSscc, where: s.organization_id == ^ctx.org_id),
               :count
             ) == 0

      operation = Operations.latest_generation_operation(ctx.org_id, ctx.batch.id)
      assert operation.status == "completed"
      assert operation.sscc_allocation_status == "not_required"
      assert operation.sscc_quantity == 0
      assert is_nil(operation.reconciliation_note)

      assert is_nil(
               Repo.get!(ThamaniDawa.Manufacturing.Batch, ctx.batch.id).shipper_preparation_method
             )
    end
  end

  describe "during-packing shipper flow" do
    test "scans, allocates, assigns and verifies an order shipper over HTTP", %{conn: conn} do
      ctx = serialized_batch_context(conn, order?: true)

      # Prepare through the authority here so the test focuses on the scan/
      # allocate/assign/verify HTTP flow rather than the prepare route itself.
      assert {:ok, _prepared} =
               Operations.prepare_shippers(ctx.org_id, ctx.batch.id, "during_packing")

      start =
        post_keyed(
          ctx.conn,
          ~p"/api/v1/manufacturer/aggregation/shipper-sessions",
          %{batch_id: ctx.batch.id}
        )

      session = json_response(start, 201)["data"]
      session_id = session["id"]

      assert session["session_type"] == "shipper"
      assert session["stage"] == "scanning"
      assert session["preparation_method"] == "during_packing"
      assert session["expected_item_count"] == 2
      assert session["captured_item_count"] == 0
      assert session["capacity_reached"] == false
      assert session["allocation_status"] == "not_required"
      assert session["label_ready"] == false
      assert session["expected_parent_sscc"] == nil
      assert session["parent_sscc"] == nil

      scanned_serials = Enum.take(ctx.serials, 2)
      [first_serial, second_serial] = scanned_serials

      first_scan =
        post_keyed(
          ctx.conn,
          ~p"/api/v1/manufacturer/aggregation/shipper-sessions/#{session_id}/scans",
          %{
            raw: product_scan(ctx, first_serial)
          }
        )

      assert json_response(first_scan, 200)["data"]["status"] == "scanning"
      assert json_response(first_scan, 200)["data"]["captured_item_count"] == 1

      second_scan =
        post_keyed(
          ctx.conn,
          ~p"/api/v1/manufacturer/aggregation/shipper-sessions/#{session_id}/scans",
          %{
            raw: product_scan(ctx, second_serial)
          }
        )

      assert json_response(second_scan, 200)["data"]["status"] == "awaiting_sscc"
      assert json_response(second_scan, 200)["data"]["captured_item_count"] == 2

      session = session_payload(ctx.conn, session_id)
      assert session["stage"] == "awaiting_sscc"
      assert session["captured_item_count"] == 2
      assert session["capacity_reached"] == true
      assert session["allocation_status"] == "pending"
      assert session["label_ready"] == false
      assert session["expected_parent_sscc"] == nil
      assert length(session["items"]) == 2

      request =
        post_keyed(
          ctx.conn,
          ~p"/api/v1/manufacturer/aggregation/shipper-sessions/#{session_id}/request-sscc",
          %{}
        )

      assert request.status == 202
      assert json_response(request, 202)["data"]["allocation"] == "pending"
      assert json_response(request, 202)["data"]["session"]["stage"] == "awaiting_sscc"
      assert MemberApiStub.create_requests() == []

      # Oban is manual in test: perform the durable allocation intent explicitly.
      operation = Operations.latest_generation_operation(ctx.org_id, ctx.batch.id)
      assert operation.sscc_allocation_status == "pending"
      assert operation.sscc_request_payload["serials"] == scanned_serials
      assert {:ok, _allocated} = Operations.allocate_identifiers(operation.id)

      [shipper_request] = MemberApiStub.shipper_sscc_requests()
      assert shipper_request["barcode"] == ctx.product.gtin
      assert shipper_request["serials"] == scanned_serials

      shipper = shipper_for_batch(ctx)

      session = session_payload(ctx.conn, session_id)
      assert session["stage"] == "awaiting_sscc"
      assert session["label_ready"] == true
      assert session["expected_parent_sscc"] == shipper.code
      assert session["parent_sscc"] == nil
      assert MemberApiStub.create_requests() == []

      assign =
        post_keyed(
          ctx.conn,
          ~p"/api/v1/manufacturer/aggregation/shipper-sessions/#{session_id}/assign-sscc",
          %{}
        )

      assert json_response(assign, 200)["data"]["stage"] == "awaiting_label_verification"
      assert json_response(assign, 200)["data"]["parent_sscc"] == shipper.code
      assert json_response(assign, 200)["data"]["parent_verification_pending"] == true
      assert json_response(assign, 200)["data"]["label_ready"] == true

      verify =
        post_keyed(
          ctx.conn,
          ~p"/api/v1/manufacturer/aggregation/shipper-sessions/#{session_id}/verify-parent",
          %{raw: "00" <> shipper.code}
        )

      assert json_response(verify, 200)["data"]["status"] == "completed"

      session = session_payload(ctx.conn, session_id)
      assert session["stage"] == "completed"
      assert session["label_ready"] == true
      assert session["expected_parent_sscc"] == shipper.code
      assert session["parent_sscc"] == shipper.code
      assert session["parent_verification_pending"] == false

      shipper = Repo.get!(ShipperSscc, shipper.id)
      assert shipper.status == "completed"
      assert Enum.sort(shipper.packed_serials) == Enum.sort(scanned_serials)
      assert shipper.count_of_trade_items == 2

      assert Repo.aggregate(
               from(
                 s in Serial,
                 where:
                   s.manufacturer_batch_id == ^ctx.batch.id and
                     s.manufacturer_shipper_sscc_id == ^shipper.id
               ),
               :count
             ) == 2
    end

    test "a duplicate product scan is rejected without increasing the captured count", %{
      conn: conn
    } do
      ctx = serialized_batch_context(conn, order?: true)

      assert {:ok, _prepared} =
               Operations.prepare_shippers(ctx.org_id, ctx.batch.id, "during_packing")

      start =
        post_keyed(
          ctx.conn,
          ~p"/api/v1/manufacturer/aggregation/shipper-sessions",
          %{batch_id: ctx.batch.id}
        )

      session_id = json_response(start, 201)["data"]["id"]
      raw = product_scan(ctx, hd(ctx.serials))

      first =
        post_keyed(
          ctx.conn,
          ~p"/api/v1/manufacturer/aggregation/shipper-sessions/#{session_id}/scans",
          %{raw: raw}
        )

      assert json_response(first, 200)["data"]["captured_item_count"] == 1

      duplicate =
        post_keyed(
          ctx.conn,
          ~p"/api/v1/manufacturer/aggregation/shipper-sessions/#{session_id}/scans",
          %{
            raw: raw
          }
        )

      assert json_response(duplicate, 422)["error"]["code"] == "duplicate_scan"

      session = session_payload(ctx.conn, session_id)
      assert session["stage"] == "scanning"
      assert session["captured_item_count"] == 1
      assert length(session["items"]) == 1
      assert MemberApiStub.create_requests() == []
    end
  end

  test "a non-manufacturer user is forbidden from the manufacturer aggregation API", %{conn: conn} do
    user = staff_fixture(%{role: :pharmacist})
    conn = authenticated_conn(conn, user)

    conn = get(conn, ~p"/api/v1/manufacturer/aggregation/batches")

    assert json_response(conn, 403)["error"]["code"] == "forbidden"
  end

  defp serialized_batch_context(conn, opts \\ []) do
    user = manufacturer_user_fixture()
    site = Sites.get_site!(user.organization_id, user.current_site_id)
    product = manufacturer_product_fixture(user.organization_id)
    order? = Keyword.get(opts, :order?, false)
    batch_no = "TEST-BATCH-#{System.unique_integer([:positive])}"
    production_date = Date.utc_today()
    expiry_date = Date.add(production_date, 365)

    attrs = %{
      "pack_quantity" => "4",
      "packs_per_shipper" => "2",
      "batch_no" => batch_no,
      "production_date" => Date.to_iso8601(production_date),
      "expiry_date" => Date.to_iso8601(expiry_date),
      "from_gln" => site.gln,
      "from_company_name" => "TEST Manufacturer Co",
      "from_address" => "1 Test Factory Road, Nairobi, Kenya"
    }

    attrs =
      if order? do
        Map.merge(attrs, %{
          "order_number" => "TEST-PO-#{System.unique_integer([:positive])}",
          "to_gln" => @destination_gln,
          "to_company_name" => "TEST Destination Clinic",
          "to_address" => "100 Test Distribution Way, Nairobi, Kenya"
        })
      else
        attrs
      end

    assert {:ok, %{batch: batch, operation: operation}} =
             Operations.prepare_generation(user.organization_id, product.id, attrs)

    assert {:ok, _operation} = Operations.allocate_identifiers(operation.id)

    serials =
      Repo.all(
        from(
          s in Serial,
          where: s.manufacturer_batch_id == ^batch.id,
          order_by: [asc: s.serial],
          select: s.serial
        )
      )

    assert length(serials) == 4

    %{
      conn: authenticated_conn(conn, user),
      user: user,
      org_id: user.organization_id,
      site: site,
      product: product,
      batch: batch,
      operation: operation,
      serials: serials
    }
  end

  defp authenticated_conn(conn, user) do
    login =
      post(build_conn(), ~p"/api/v1/login", %{
        email: user.email,
        password: valid_user_password()
      })

    token = json_response(login, 200)["access_token"]
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  defp post_keyed(conn, path, params) do
    conn
    |> put_req_header("idempotency-key", Ecto.UUID.generate())
    |> post(path, params)
  end

  defp session_payload(conn, session_id) do
    conn = get(conn, ~p"/api/v1/manufacturer/aggregation/sessions/#{session_id}")
    json_response(conn, 200)["data"]
  end

  defp product_scan(ctx, serial) do
    "01#{ctx.product.gtin}10#{ctx.batch.batch_no}#{<<29>>}21#{serial}"
  end

  defp shipper_for_batch(%{org_id: org_id, batch: batch}) do
    Repo.one!(
      from(
        s in ShipperSscc,
        join: sb in SsccBatch,
        on: sb.manufacturer_shipper_sscc_id == s.id,
        where: s.organization_id == ^org_id and sb.manufacturer_batch_id == ^batch.id,
        select: s
      )
    )
  end
end
