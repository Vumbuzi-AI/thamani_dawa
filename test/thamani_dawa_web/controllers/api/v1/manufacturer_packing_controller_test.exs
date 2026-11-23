defmodule ThamaniDawaWeb.Api.V1.ManufacturerPackingControllerTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.DistributorFixtures
  import ThamaniDawa.ManufacturerFixtures

  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Epcis.Outbox
  alias ThamaniDawa.Manufacturing

  setup do
    organization = manufacturer_organization_fixture()
    site = manufacturing_site_fixture(organization.id)
    user = manufacturer_user_fixture(%{organization_id: organization.id, site_id: site.id})
    product = manufacturer_product_fixture(organization.id)

    {:ok, %{batch: batch}} =
      Manufacturing.generate_primary_serials(
        organization.id,
        product,
        %{
          "batch_no" => "LOT-AGG",
          "production_date" => "2026-11-20",
          "expiry_date" => "2027-11-20"
        },
        3,
        site.gln
      )

    {:ok, sscc} =
      Manufacturing.create_sscc(organization.id, product, [batch], %{"count_of_trade_items" => 2})

    {:ok, organization: organization, site: site, user: user, product: product, sscc: sscc}
  end

  test "an aggregation: draft, scan, submit, approve", ctx do
    targets =
      ctx.user |> auth() |> get(~p"/api/v1/manufacturer/aggregations/ssccs") |> json_response(200)

    assert Enum.map(targets["data"], & &1["id"]) == [ctx.sscc.id]

    check =
      ctx.user
      |> auth()
      |> post(
        ~p"/api/v1/manufacturer/aggregations/classify",
        Jason.encode!(%{sscc_id: ctx.sscc.id, serial: "9999"})
      )
      |> json_response(200)

    assert check["data"]["validation_status"] == "unknown_serial"

    draft =
      ctx.user
      |> auth()
      |> post(~p"/api/v1/manufacturer/aggregations", Jason.encode!(%{sscc_id: ctx.sscc.id}))
      |> json_response(201)

    assert draft["data"]["status"] == "draft"
    id = draft["data"]["id"]

    empty =
      ctx.user |> auth() |> post(~p"/api/v1/manufacturer/aggregations/#{id}/submit")

    assert json_response(empty, 422)["error"]["code"] == "no_items"

    scanned = ctx |> scan(id, "0001") |> json_response(201)
    assert [%{"serial" => "0001", "validation_status" => "ok"}] = scanned["data"]["items"]

    assert ctx |> scan(id, "0001") |> json_response(409) |> get_in(["error", "code"]) ==
             "duplicate_serial"

    ctx |> scan(id, "0002") |> json_response(201)

    submitted =
      ctx.user
      |> auth()
      |> post(~p"/api/v1/manufacturer/aggregations/#{id}/submit")
      |> json_response(200)

    assert submitted["data"]["status"] == "submitted"

    assert ctx |> scan(id, "0003") |> json_response(409) |> get_in(["error", "code"]) ==
             "invalid_state"

    listed =
      ctx.user
      |> auth()
      |> get(~p"/api/v1/manufacturer/aggregations?status=submitted")
      |> json_response(200)

    assert [%{"id" => ^id, "item_count" => 2}] = listed["data"]

    approved =
      ctx.user
      |> auth()
      |> post(~p"/api/v1/manufacturer/aggregations/#{id}/approve")
      |> json_response(200)

    assert approved["data"]["status"] == "approved"

    linked = Manufacturing.list_serials_for_sscc(ctx.organization.id, ctx.sscc.id)
    assert Enum.count(linked, &(&1.manufacturer_shipper_sscc_id == ctx.sscc.id)) == 2
  end

  test "creating with serials submits straight away, but only valid ones", ctx do
    invalid =
      ctx.user
      |> auth()
      |> post(
        ~p"/api/v1/manufacturer/aggregations",
        Jason.encode!(%{sscc_id: ctx.sscc.id, serials: ["0001", "nope"]})
      )
      |> json_response(422)

    assert invalid["error"]["code"] == "invalid_serials"

    assert [%{"serial" => "nope", "validation_status" => "unknown_serial"}] =
             invalid["error"]["serials"]

    created =
      ctx.user
      |> auth()
      |> post(
        ~p"/api/v1/manufacturer/aggregations",
        Jason.encode!(%{sscc_id: ctx.sscc.id, serials: ["0001", "0002", "0003"]})
      )
      |> json_response(201)

    assert created["data"]["status"] == "submitted"

    # Three serials into a shipper that holds two.
    over =
      ctx.user
      |> auth()
      |> post(~p"/api/v1/manufacturer/aggregations/#{created["data"]["id"]}/approve")
      |> json_response(422)

    assert over["error"]["code"] == "over_capacity"
    assert over["error"]["capacity"] == 2

    rejected =
      ctx.user
      |> auth()
      |> post(
        ~p"/api/v1/manufacturer/aggregations/#{created["data"]["id"]}/reject",
        Jason.encode!(%{reason: "Wrong shipper"})
      )
      |> json_response(200)

    assert rejected["data"]["status"] == "rejected"
    assert rejected["data"]["rejection_reason"] == "Wrong shipper"
  end

  test "a manufacturer shipment: create, packed by mobile, approved", ctx do
    destination = manufacturing_site_fixture(manufacturer_organization_fixture().id)

    created =
      ctx.user
      |> auth()
      |> post(
        ~p"/api/v1/manufacturer/shipments",
        Jason.encode!(%{order_number: "MO-API-1", destination_gln: destination.gln})
      )
      |> json_response(201)

    # The origin defaults to the user's current site, as on the web.
    assert created["data"]["origin_gln"] == ctx.site.gln
    assert created["data"]["status"] == "draft"
    id = created["data"]["id"]

    early =
      ctx.user |> auth() |> post(~p"/api/v1/manufacturer/shipments/#{id}/approve")

    assert json_response(early, 409)["error"]["status"] == "draft"

    mobile_user = mobile_user_fixture(ctx.organization.id, %{"site_id" => ctx.site.id})
    unit = received_unit_fixture(ctx.organization.id, ctx.site.id, ctx.user.id)
    prepay_allowance_fixture(ctx.organization.id, ctx.user)
    {:ok, _shipment} = Distributor.select_shipment(mobile_user, id)
    {:ok, shipper} = Distributor.create_shipper(mobile_user, id, %{})

    {:ok, _item} =
      Distributor.scan_item(mobile_user, shipper.id, %{"raw_data_matrix" => data_matrix_for(unit)})

    {:ok, _shipment} = Distributor.submit_shipment(mobile_user, id)

    listed =
      ctx.user
      |> auth()
      |> get(~p"/api/v1/manufacturer/shipments?status=submitted")
      |> json_response(200)

    assert [%{"id" => ^id}] = listed["data"]

    approved =
      ctx.user
      |> auth()
      |> post(~p"/api/v1/manufacturer/shipments/#{id}/approve")
      |> json_response(200)

    assert approved["data"]["status"] == "approved"
    assert [%{"sscc" => sscc}] = approved["data"]["shippers"]
    assert sscc

    again =
      ctx.user
      |> auth()
      |> post(~p"/api/v1/manufacturer/shipments/#{id}/approve")
      |> json_response(200)

    assert again["data"]["status"] == "approved"

    assert Enum.any?(
             Outbox.list_events(ctx.organization.id, tier: "manufacturer"),
             &(&1.event_type == "shipping")
           )
  end

  test "a distributor-tier shipment is not visible here", ctx do
    distributor_shipment =
      shipment_fixture(ctx.organization.id, ctx.user, %{
        warehouse: ctx.site,
        destination: destination_fixture()
      })

    assert ctx.user
           |> auth()
           |> get(~p"/api/v1/manufacturer/shipments/#{distributor_shipment.id}")
           |> json_response(404)
  end

  defp scan(ctx, id, serial) do
    ctx.user
    |> auth()
    |> post(~p"/api/v1/manufacturer/aggregations/#{id}/items", Jason.encode!(%{serial: serial}))
  end

  defp auth(user) do
    conn =
      post(build_conn(), ~p"/api/v1/login", %{email: user.email, password: valid_user_password()})

    token = json_response(conn, 200)["access_token"]

    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("idempotency-key", "test-#{System.unique_integer([:positive])}")
  end
end
