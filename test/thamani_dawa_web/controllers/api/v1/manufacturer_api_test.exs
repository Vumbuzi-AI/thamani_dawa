defmodule ThamaniDawaWeb.Api.V1.ManufacturerApiTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Ecto.Query
  import ThamaniDawa.DistributorFixtures
  import ThamaniDawa.ManufacturerFixtures

  alias ThamaniDawa.GS1.MemberApiStub
  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Manufacturing.Batch
  alias ThamaniDawa.Manufacturing.Shipment
  alias ThamaniDawa.Repo

  @device "test-device-1"

  setup do
    organization = manufacturer_organization_fixture()
    site = manufacturing_site_fixture(organization.id)
    product = manufacturer_product_fixture(organization.id)
    batch = manufacturer_batch_fixture(organization.id, product.id)
    {packer, pin} = manufacturer_packer_fixture(organization.id, site_id: site.id)
    destination = manufacturing_site_fixture(manufacturer_organization_fixture().id)

    {:ok, _} =
      Manufacturing.generate_primary_serials(
        organization.id,
        product,
        %{
          "batch_no" => batch.batch_no,
          "production_date" => Date.to_iso8601(batch.production_date),
          "expiry_date" => Date.to_iso8601(batch.expiry_date)
        },
        3,
        site.gln
      )

    %{
      organization: organization,
      site: site,
      product: product,
      batch: batch,
      packer: packer,
      pin: pin,
      destination: destination
    }
  end

  test "login returns opaque tokens and a string user id", %{
    conn: conn,
    packer: packer,
    pin: pin
  } do
    conn = login(conn, packer.username, pin)
    body = json_response(conn, 200)

    assert is_binary(body["access_token"])
    assert is_binary(body["refresh_token"])
    assert body["user"]["id"] == to_string(packer.id)
    assert body["user"]["username"] == packer.username
    assert is_binary(body["user"]["organization_name"])
  end

  test "Expo web origin is allowed on login", %{conn: conn, packer: packer, pin: pin} do
    conn =
      conn
      |> put_req_header("origin", "http://localhost:8081")
      |> login(packer.username, pin)

    assert json_response(conn, 200)
    assert get_resp_header(conn, "access-control-allow-origin") == ["http://localhost:8081"]
  end

  test "Expo web preflight is allowed", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", "http://localhost:8081")
      |> put_req_header("access-control-request-method", "POST")
      |> put_req_header("access-control-request-headers", "content-type,x-device-id")
      |> options("/api/v1/manufacturer/login")

    assert conn.status == 204
    assert get_resp_header(conn, "access-control-allow-origin") == ["http://localhost:8081"]
  end

  test "a bad PIN is invalid credentials", %{conn: conn, packer: packer} do
    conn = login(conn, packer.username, "0000")
    assert json_response(conn, 401)["error"]["code"] == "invalid_credentials"
  end

  test "a distributor packer cannot use the manufacturer login", %{conn: conn} do
    org = distributor_organization_fixture()
    warehouse = warehouse_fixture(org.id)
    {packer, pin} = manufacturer_packer_fixture(org.id, site_id: warehouse.id)

    conn = login(conn, packer.username, pin)
    assert json_response(conn, 403)["error"]["code"] == "account_inactive"
  end

  test "five wrong PINs lock the account", %{conn: conn, packer: packer, pin: pin} do
    Enum.each(1..5, fn _ -> login(conn, packer.username, "0000") end)

    conn = login(conn, packer.username, pin)
    body = json_response(conn, 423)
    assert body["error"]["code"] == "account_locked"
    assert is_binary(body["error"]["locked_until"])
  end

  test "logout revokes the access token", %{packer: packer, pin: pin} do
    token = access_token(packer.username, pin)

    conn =
      build_conn()
      |> authed(token)
      |> post(~p"/api/v1/manufacturer/logout")

    assert response(conn, 204)

    conn =
      build_conn()
      |> authed(token)
      |> get(~p"/api/v1/manufacturer/batches")

    assert json_response(conn, 401)["error"]["code"] == "unauthorized"
  end

  test "lists lots with unpacked serials and string ids", %{
    packer: packer,
    pin: pin,
    batch: batch,
    product: product
  } do
    conn =
      build_conn()
      |> authed(access_token(packer.username, pin))
      |> get(~p"/api/v1/manufacturer/batches")

    [row] = json_response(conn, 200)["data"]
    assert row["id"] == to_string(batch.id)
    assert row["gtin"] == product.gtin
    assert row["batch_no"] == batch.batch_no
    assert row["unpacked_count"] == 3
    assert row["packed_count"] == 0
    assert row["open_box_id"] == nil
  end

  test "opening a batch copies GS1 serials into the local loose count", %{
    conn: conn,
    packer: packer,
    pin: pin,
    batch: batch,
    organization: organization
  } do
    Repo.delete_all(from s in ThamaniDawa.Manufacturing.Serial, where: s.manufacturer_batch_id == ^batch.id)

    from(b in Batch, where: b.id == ^batch.id)
    |> Repo.update_all(set: [issued_count: 0, packed_count: 0])

    listed =
      conn
      |> authed(access_token(packer.username, pin))
      |> get(~p"/api/v1/manufacturer/batches")
      |> json_response(200)
      |> Map.fetch!("data")
      |> Enum.find(&(&1["id"] == to_string(batch.id)))

    assert listed["unpacked_count"] == 0

    shown =
      build_conn()
      |> authed(access_token(packer.username, pin))
      |> get(~p"/api/v1/manufacturer/batches/#{batch.id}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert shown["unpacked_count"] == 3
    assert length(serials_for(organization.id, batch.id)) == 3
  end

  test "opening a box on a batch with no GS1 serials is no_unpacked", %{
    conn: conn,
    packer: packer,
    pin: pin,
    product: product,
    site: site,
    destination: destination
  } do
    empty = manufacturer_batch_fixture(packer.organization_id, product.id)
    token = access_token(packer.username, pin)

    conn
    |> authed(token)
    |> put(~p"/api/v1/manufacturer/batches/#{empty.id}/parties", %{
      from_gln: site.gln,
      to_gln: destination.gln
    })
    |> json_response(200)

    conn =
      build_conn()
      |> authed(token)
      |> post(~p"/api/v1/manufacturer/batches/#{empty.id}/box")

    assert json_response(conn, 409)["error"]["code"] == "no_unpacked"
  end

  test "lists empty lots as well as loose ones", %{
    conn: conn,
    packer: packer,
    pin: pin,
    batch: batch,
    product: product
  } do
    empty = manufacturer_batch_fixture(packer.organization_id, product.id)

    ids =
      conn
      |> authed(access_token(packer.username, pin))
      |> get(~p"/api/v1/manufacturer/batches")
      |> json_response(200)
      |> Map.fetch!("data")
      |> Enum.map(& &1["id"])

    assert to_string(batch.id) in ids
    assert to_string(empty.id) in ids
  end

  test "resolve maps a unit serial to its lot", %{
    conn: conn,
    packer: packer,
    pin: pin,
    batch: batch,
    organization: organization
  } do
    [serial | _] = serials_for(organization.id, batch.id)

    body =
      conn
      |> authed(access_token(packer.username, pin))
      |> post(~p"/api/v1/manufacturer/resolve", %{raw: serial})
      |> json_response(200)

    assert body["data"]["serial"] == serial
    assert body["data"]["batch"]["id"] == to_string(batch.id)
    assert body["data"]["batch"]["batch_no"] == batch.batch_no
  end

  test "resolve maps a lot label to its lot", %{
    conn: conn,
    packer: packer,
    pin: pin,
    batch: batch
  } do
    body =
      conn
      |> authed(access_token(packer.username, pin))
      |> post(~p"/api/v1/manufacturer/resolve", %{raw: "(10)#{batch.batch_no}"})
      |> json_response(200)

    assert body["data"]["serial"] == nil
    assert body["data"]["batch"]["id"] == to_string(batch.id)
  end

  test "resolve of an unknown code is not found", %{conn: conn, packer: packer, pin: pin} do
    conn =
      conn
      |> authed(access_token(packer.username, pin))
      |> post(~p"/api/v1/manufacturer/resolve", %{raw: "no-such-lot"})

    assert json_response(conn, 404)["error"]["code"] == "not_found"
  end

  test "claim accepts a GS1 unit when the lot text only differs by case", %{
    organization: organization,
    site: site,
    packer: packer,
    pin: pin,
    batch: batch,
    product: product,
    destination: destination
  } do
    token = access_token(packer.username, pin)
    box_id = open_ready_box(token, batch, site, destination)
    [serial | _] = serials_for(organization.id, batch.id)
    raw = "(01)#{product.gtin}(21)#{serial}(10)#{String.upcase(batch.batch_no)}"

    resolved =
      build_conn()
      |> authed(token)
      |> post(~p"/api/v1/manufacturer/resolve", %{raw: raw})
      |> json_response(200)
      |> Map.fetch!("data")

    assert resolved["batch"]["id"] == to_string(batch.id)
    assert resolved["serial"] == serial

    claimed =
      build_conn()
      |> authed(token)
      |> post(~p"/api/v1/manufacturer/boxes/#{box_id}/scans", %{raw: raw})
      |> json_response(201)
      |> Map.fetch!("data")

    assert claimed["serial"] == serial
    assert claimed["batch_no"] == batch.batch_no
  end

  test "opening a box without parties is parties_required", %{
    packer: packer,
    pin: pin,
    batch: batch
  } do
    conn =
      build_conn()
      |> authed(access_token(packer.username, pin))
      |> post(~p"/api/v1/manufacturer/batches/#{batch.id}/box")

    assert json_response(conn, 409)["error"]["code"] == "parties_required"
  end

  test "lists plant GLNs for the destination picker", %{
    conn: conn,
    packer: packer,
    pin: pin,
    site: site
  } do
    rows =
      conn
      |> authed(access_token(packer.username, pin))
      |> get("/api/v1/manufacturer/glns", %{q: site.name})
      |> json_response(200)
      |> Map.fetch!("data")

    assert Enum.any?(rows, &(&1["gln"] == site.gln and &1["name"] == site.name))
  end

  test "claims a serial, repeats on the same box, and rejects a second packer", %{
    organization: organization,
    site: site,
    packer: packer,
    pin: pin,
    batch: batch,
    product: product,
    destination: destination
  } do
    token = access_token(packer.username, pin)
    box_id = open_ready_box(token, batch, site, destination)
    [serial | rest] = serials_for(organization.id, batch.id)

    conn =
      build_conn()
      |> authed(token)
      |> post(~p"/api/v1/manufacturer/boxes/#{box_id}/scans", %{raw: serial})

    body = json_response(conn, 201)["data"]
    assert body["serial"] == serial
    assert body["gtin"] == product.gtin
    assert body["batch_no"] == batch.batch_no

    conn =
      build_conn()
      |> authed(token)
      |> post(~p"/api/v1/manufacturer/boxes/#{box_id}/scans", %{raw: serial})

    assert json_response(conn, 200)["data"]["serial"] == serial

    {other, other_pin} = manufacturer_packer_fixture(organization.id, site_id: site.id)
    other_token = access_token(other.username, other_pin)
    other_box = open_ready_box(other_token, batch, site, destination)

    conn =
      build_conn()
      |> authed(other_token)
      |> post(~p"/api/v1/manufacturer/boxes/#{other_box}/scans", %{raw: serial})

    assert json_response(conn, 409)["error"]["code"] == "already_claimed"

    assert {:ok, remaining} =
             Manufacturing.fetch_unpacked_serials(organization.id, product.gtin, batch.batch_no)

    assert remaining == rest
  end

  test "save mints one SSCC, is idempotent, and does not create a shipment", %{
    organization: organization,
    site: site,
    packer: packer,
    pin: pin,
    batch: batch,
    product: product,
    destination: destination
  } do
    token = access_token(packer.username, pin)
    box_id = open_ready_box(token, batch, site, destination)
    [serial | _] = serials_for(organization.id, batch.id)

    conn =
      build_conn()
      |> authed(token)
      |> post(~p"/api/v1/manufacturer/boxes/#{box_id}/scans", %{raw: serial})

    assert json_response(conn, 201)

    conn =
      build_conn()
      |> authed(token)
      |> post(~p"/api/v1/manufacturer/boxes/#{box_id}/save")

    assert json_response(conn, 400)["error"]["code"] == "bad_request"

    key = Ecto.UUID.generate()

    conn =
      build_conn()
      |> authed(token)
      |> put_req_header("idempotency-key", key)
      |> post(~p"/api/v1/manufacturer/boxes/#{box_id}/save")

    saved = json_response(conn, 200)["data"]
    assert saved["status"] == "saved"
    assert is_binary(saved["sscc"])
    assert saved["count"] == 1
    assert saved["gtin"] == product.gtin
    assert saved["from_gln"] == site.gln
    assert saved["to_gln"] == destination.gln

    before = length(MemberApiStub.shipper_sscc_requests())

    conn =
      build_conn()
      |> authed(token)
      |> put_req_header("idempotency-key", key)
      |> post(~p"/api/v1/manufacturer/boxes/#{box_id}/save")

    again = json_response(conn, 200)["data"]
    assert again["sscc"] == saved["sscc"]
    assert length(MemberApiStub.shipper_sscc_requests()) == before

    assert Repo.aggregate(
             from(s in Shipment, where: s.organization_id == ^organization.id),
             :count
           ) == 0

    [row] =
      build_conn()
      |> authed(token)
      |> get(~p"/api/v1/manufacturer/batches")
      |> json_response(200)
      |> Map.fetch!("data")
      |> Enum.filter(&(&1["id"] == to_string(batch.id)))

    assert row["packed_count"] == 1
    assert row["unpacked_count"] == 2
  end

  test "saving an empty draft is empty_box", %{
    site: site,
    packer: packer,
    pin: pin,
    batch: batch,
    destination: destination
  } do
    token = access_token(packer.username, pin)
    box_id = open_ready_box(token, batch, site, destination)

    conn =
      build_conn()
      |> authed(token)
      |> put_req_header("idempotency-key", Ecto.UUID.generate())
      |> post(~p"/api/v1/manufacturer/boxes/#{box_id}/save")

    assert json_response(conn, 422)["error"]["code"] == "empty_box"
  end

  defp login(conn, username, pin) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("x-device-id", @device)
    |> post(~p"/api/v1/manufacturer/login", %{username: username, pin: pin})
  end

  defp access_token(username, pin) do
    json_response(login(build_conn(), username, pin), 200)["access_token"]
  end

  defp authed(conn, token) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("x-device-id", @device)
    |> put_req_header("authorization", "Bearer " <> token)
  end

  defp open_ready_box(token, batch, site, destination) do
    conn =
      build_conn()
      |> authed(token)
      |> put(~p"/api/v1/manufacturer/batches/#{batch.id}/parties", %{
        from_gln: site.gln,
        to_gln: destination.gln
      })

    assert json_response(conn, 200)

    conn =
      build_conn()
      |> authed(token)
      |> post(~p"/api/v1/manufacturer/batches/#{batch.id}/box")

    status = conn.status
    assert status in [200, 201]
    body = json_response(conn, status)["data"]
    assert body["status"] == "draft"
    body["id"]
  end

  defp serials_for(organization_id, batch_id) do
    organization_id
    |> Manufacturing.list_serials(batch_id)
    |> Enum.map(& &1.serial)
    |> Enum.sort()
  end
end
