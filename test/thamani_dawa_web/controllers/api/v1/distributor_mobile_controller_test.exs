defmodule ThamaniDawaWeb.Api.V1.DistributorMobileControllerTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.DistributorFixtures

  alias ThamaniDawa.Distributor.MobileUser
  alias ThamaniDawa.Repo

  setup do
    organization = distributor_organization_fixture()
    user = distributor_user_fixture(%{organization_id: organization.id})
    warehouse = warehouse_fixture(organization.id)
    destination = destination_fixture(organization.id)

    mobile_user =
      organization.id
      |> mobile_user_fixture()
      |> MobileUser.pin_changeset("4321")
      |> Repo.update!()

    shipment =
      shipment_fixture(organization.id, user, %{warehouse: warehouse, destination: destination})

    unit = received_unit_fixture(organization.id, warehouse.id, user.id)

    {:ok,
     organization: organization,
     user: user,
     mobile_user: mobile_user,
     shipment: shipment,
     unit: unit}
  end

  test "signs in with username and PIN, and a wrong PIN is refused", ctx do
    body =
      build_conn()
      |> post(~p"/api/v1/distributor/mobile/login", %{
        username: ctx.mobile_user.username,
        pin: "4321"
      })
      |> json_response(200)

    assert body["access_token"]
    assert body["refresh_token"]
    assert body["mobile_user"]["username"] == ctx.mobile_user.username
    refute Map.has_key?(body["mobile_user"], "pin_hash")

    wrong =
      post(build_conn(), ~p"/api/v1/distributor/mobile/login", %{
        username: ctx.mobile_user.username,
        pin: "0000"
      })

    assert json_response(wrong, 401)["error"]["code"] == "invalid_credentials"
  end

  test "refresh rotates the token pair", ctx do
    session = login(ctx.mobile_user)

    refreshed =
      build_conn()
      |> post(~p"/api/v1/distributor/mobile/token/refresh", %{
        refresh_token: session["refresh_token"]
      })
      |> json_response(200)

    assert refreshed["access_token"] != session["access_token"]

    stale = session["access_token"] |> bearer() |> get(~p"/api/v1/distributor/mobile/me")
    assert json_response(stale, 401)["error"]["code"] == "unauthorized"
  end

  test "a web API token cannot open the packing routes, and vice versa", ctx do
    web =
      build_conn()
      |> post(~p"/api/v1/login", %{email: ctx.user.email, password: valid_user_password()})
      |> json_response(200)

    conn = web["access_token"] |> bearer() |> get(~p"/api/v1/distributor/mobile/shipments")
    assert json_response(conn, 401)

    mobile = login(ctx.mobile_user)
    conn = mobile["access_token"] |> bearer() |> get(~p"/api/v1/me")
    assert json_response(conn, 401)
  end

  test "find, claim, add a shipper, scan, and submit a shipment", ctx do
    token = login(ctx.mobile_user)["access_token"]

    found =
      token
      |> bearer()
      |> get(
        ~p"/api/v1/distributor/mobile/shipments/search?order_number=#{ctx.shipment.order_number}"
      )
      |> json_response(200)

    assert Enum.map(found["data"], & &1["id"]) == [ctx.shipment.id]

    claimed =
      token
      |> bearer()
      |> post(~p"/api/v1/distributor/mobile/shipments/#{ctx.shipment.id}/select")
      |> json_response(200)

    assert claimed["data"]["assigned_mobile_user_id"] == ctx.mobile_user.id

    with_shipper =
      token
      |> bearer()
      |> post(~p"/api/v1/distributor/mobile/shipments/#{ctx.shipment.id}/shippers", %{})
      |> json_response(200)

    [shipper] = with_shipper["data"]["shippers"]

    scanned =
      token
      |> bearer()
      |> post(~p"/api/v1/distributor/mobile/shippers/#{shipper["id"]}/items", %{
        raw_data_matrix: data_matrix_for(ctx.unit)
      })
      |> json_response(201)

    assert scanned["data"]["serial"] == ctx.unit.serial
    assert scanned["data"]["gtin"] == ctx.unit.gtin

    submitted =
      token
      |> bearer()
      |> post(~p"/api/v1/distributor/mobile/shipments/#{ctx.shipment.id}/submit")
      |> json_response(200)

    assert submitted["data"]["status"] == "submitted"

    list =
      token |> bearer() |> get(~p"/api/v1/distributor/mobile/shipments") |> json_response(200)

    assert Enum.map(list["data"], & &1["id"]) == [ctx.shipment.id]
    assert list["meta"]["total"] == 1
  end

  test "a shipment held by another packer cannot be claimed", ctx do
    other = mobile_user_fixture(ctx.organization.id)
    {:ok, _} = ThamaniDawa.Distributor.select_shipment(other, ctx.shipment.id)

    conn =
      ctx.mobile_user
      |> login()
      |> Map.fetch!("access_token")
      |> bearer()
      |> post(~p"/api/v1/distributor/mobile/shipments/#{ctx.shipment.id}/select")

    assert json_response(conn, 409)["error"]["code"] == "already_assigned"
  end

  test "an unreadable scan is a clear 422", ctx do
    token = login(ctx.mobile_user)["access_token"]
    {:ok, _} = ThamaniDawa.Distributor.select_shipment(ctx.mobile_user, ctx.shipment.id)

    {:ok, shipper} =
      ThamaniDawa.Distributor.create_shipper(ctx.mobile_user, ctx.shipment.id, %{})

    conn =
      token
      |> bearer()
      |> post(~p"/api/v1/distributor/mobile/shippers/#{shipper.id}/items", %{})

    assert json_response(conn, 422)["error"]["code"] == "invalid_scan"
  end

  test "another organization's shipment is not found", ctx do
    other_org = distributor_organization_fixture()
    other_user = distributor_user_fixture(%{organization_id: other_org.id})
    foreign = shipment_fixture(other_org.id, other_user)

    conn =
      ctx.mobile_user
      |> login()
      |> Map.fetch!("access_token")
      |> bearer()
      |> post(~p"/api/v1/distributor/mobile/shipments/#{foreign.id}/select")

    assert json_response(conn, 404)["error"]["code"] == "not_found"
  end

  defp login(mobile_user) do
    build_conn()
    |> post(~p"/api/v1/distributor/mobile/login", %{username: mobile_user.username, pin: "4321"})
    |> json_response(200)
  end

  defp bearer(token) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json")
  end
end
