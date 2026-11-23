defmodule ThamaniDawaWeb.Api.V1.ManufacturerControllerTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.ManufacturerFixtures

  setup do
    organization = manufacturer_organization_fixture()

    site =
      manufacturing_site_fixture(organization.id, %{name: "Main Plant", address: "1 Plant Rd"})

    user = manufacturer_user_fixture(%{organization_id: organization.id, site_id: site.id})
    product = manufacturer_product_fixture(organization.id)
    {:ok, organization: organization, site: site, user: user, product: product}
  end

  test "only manufacturer staff get in" do
    pharmacist = staff_fixture(%{role: :pharmacist})

    body =
      pharmacist |> auth() |> get(~p"/api/v1/manufacturer/dashboard") |> json_response(403)

    assert body["error"]["code"] == "forbidden"
  end

  test "dashboard counts and the portal in /me", ctx do
    body = ctx.user |> auth() |> get(~p"/api/v1/manufacturer/dashboard") |> json_response(200)
    assert body["data"]["counts"]["products"] == 1
    assert body["data"]["awaiting_review"] == %{"aggregations" => 0, "shipments" => 0}

    me = ctx.user |> auth() |> get(~p"/api/v1/me") |> json_response(200)
    assert "manufacturer" in me["data"]["portals"]
  end

  test "lists, creates and shows products by id and GTIN", ctx do
    listed = ctx.user |> auth() |> get(~p"/api/v1/manufacturer/products") |> json_response(200)
    assert [%{"gtin" => gtin, "serial_count" => 0, "sscc_count" => 0}] = listed["data"]
    assert gtin == ctx.product.gtin
    refute Map.has_key?(hd(listed["data"]), "licence_key")

    created =
      ctx.user
      |> auth()
      |> post(
        ~p"/api/v1/manufacturer/products",
        Jason.encode!(%{gtin: "06141410000108", name: "Amoxicillin 250mg"})
      )
      |> json_response(201)

    assert created["data"]["name"] == "Amoxicillin 250mg"
    assert created["data"]["batches"] == []

    by_id =
      ctx.user
      |> auth()
      |> get(~p"/api/v1/manufacturer/products/#{ctx.product.id}")
      |> json_response(200)

    by_gtin =
      ctx.user
      |> auth()
      |> get(~p"/api/v1/manufacturer/products/gtin/#{ctx.product.gtin}")
      |> json_response(200)

    assert by_id["data"]["id"] == by_gtin["data"]["id"]

    foreign = manufacturer_product_fixture(manufacturer_organization_fixture().id)

    assert ctx.user
           |> auth()
           |> get(~p"/api/v1/manufacturer/products/#{foreign.id}")
           |> json_response(404)
  end

  test "make-to-stock generates serials at the current site and lists them", ctx do
    generated = generate(ctx, %{mode: "stock", primary_quantity: 3})

    assert generated["data"]["batch"]["batch_no"] == "LOT-API-1"
    assert length(generated["data"]["serials"]) == 3
    assert generated["data"]["shippers"] == []
    [first | _] = generated["data"]["serials"]
    assert first["gs1_text"] =~ "(10)LOT-API-1"
    assert first["gs1_text"] =~ "(21)#{first["serial"]}"

    batch_id = generated["data"]["batch"]["id"]

    batches =
      ctx.user
      |> auth()
      |> get(~p"/api/v1/manufacturer/products/#{ctx.product.id}/batches")
      |> json_response(200)

    assert [%{"id" => ^batch_id, "serial_count" => 3}] = batches["data"]

    serials =
      ctx.user
      |> auth()
      |> get(
        ~p"/api/v1/manufacturer/products/#{ctx.product.id}/batches/#{batch_id}/serials?per_page=2"
      )
      |> json_response(200)

    assert length(serials["data"]) == 2
    assert serials["meta"]["total"] == 3

    csv =
      ctx.user
      |> auth()
      |> get(
        ~p"/api/v1/manufacturer/products/#{ctx.product.id}/batches/#{batch_id}/serials/export?format=csv"
      )

    assert response_content_type(csv, :csv)
    [header | rows] = csv |> response(200) |> String.split("\r\n", trim: true)
    assert header == "gtin,batch,production_date,expiry_date,serial"
    assert length(rows) == 3

    json =
      ctx.user
      |> auth()
      |> get(
        ~p"/api/v1/manufacturer/products/#{ctx.product.id}/batches/#{batch_id}/serials/export"
      )
      |> json_response(200)

    assert [%{"gtin" => _, "batch" => "LOT-API-1", "serial" => _} | _] = json["data"]

    inventory =
      ctx.user |> auth() |> get(~p"/api/v1/manufacturer/inventory") |> json_response(200)

    assert [%{"batches" => [%{"serial_count" => 3}]}] = inventory["data"]
  end

  test "the wizard's rules apply: bad quantities, dates and modes are refused", ctx do
    body =
      ctx
      |> generate_conn(%{
        mode: "stock",
        primary_quantity: 101,
        production_date: "2026-11-20",
        expiry_date: "2026-11-01"
      })
      |> json_response(422)

    assert body["error"]["code"] == "validation_failed"
    assert body["error"]["fields"]["primary_quantity"] == ["Primary quantity cannot exceed 100"]
    assert body["error"]["fields"]["expiry_date"] == ["must be after the production date"]

    mode = ctx |> generate_conn(%{mode: "later"}) |> json_response(422)
    assert mode["error"]["code"] == "invalid_mode"

    order =
      ctx
      |> generate_conn(%{mode: "order", primary_quantity: 2, shipper_quantity: 3, to_gln: ""})
      |> json_response(422)

    assert order["error"]["fields"]["to_gln"] == ["To GLN is required"]
    assert order["error"]["fields"]["shipper_quantity"] == ["cannot exceed the primary quantity"]
  end

  test "make-to-order mints shippers under a pallet, with labels and exports", ctx do
    destination = manufacturing_site_fixture(manufacturer_organization_fixture().id)

    generated =
      generate(ctx, %{
        mode: "order",
        primary_quantity: 4,
        shipper_quantity: 2,
        to_gln: destination.gln
      })

    assert generated["data"]["pallet"]["from_company_name"] == "Main Plant"
    assert generated["data"]["pallet"]["to_company_name"] == destination.name
    assert [shipper, _second] = generated["data"]["shippers"]

    ssccs =
      ctx.user
      |> auth()
      |> get(~p"/api/v1/manufacturer/products/#{ctx.product.id}/ssccs")
      |> json_response(200)

    assert length(ssccs["data"]) == 2
    assert Enum.all?(ssccs["data"], &(&1["serial_count"] == 2))

    shown =
      ctx.user
      |> auth()
      |> get(~p"/api/v1/manufacturer/ssccs/#{shipper["id"]}")
      |> json_response(200)

    assert shown["data"]["pallet"]["code"]

    serials =
      ctx.user
      |> auth()
      |> get(~p"/api/v1/manufacturer/ssccs/#{shipper["id"]}/serials")
      |> json_response(200)

    assert serials["meta"]["total"] == 2

    label =
      ctx.user
      |> auth()
      |> get(~p"/api/v1/manufacturer/ssccs/#{shipper["id"]}/label")
      |> json_response(200)

    assert label["data"]["gs1_text"] == "(00)#{shipper["code"]}"
    assert label["data"]["from_company_name"] == "Main Plant"
    assert label["data"]["to_company_name"] == destination.name

    csv =
      ctx.user
      |> auth()
      |> get(~p"/api/v1/manufacturer/ssccs/#{shipper["id"]}/export?format=csv")
      |> response(200)

    assert [header, _row1, _row2] = String.split(csv, "\r\n", trim: true)
    assert header == "sscc,gtin,batch,serial"
  end

  test "GS1 prefixes need manufacturer admin access", ctx do
    assert ctx.user |> auth() |> get(~p"/api/v1/manufacturer/gs1-prefixes") |> json_response(403)

    admin = user_fixture(%{organization_id: ctx.organization.id})

    body = admin |> auth() |> get(~p"/api/v1/manufacturer/gs1-prefixes") |> json_response(200)
    assert [%{"prefix" => "0614141", "is_primary" => true}] = body["data"]
  end

  defp generate(ctx, attrs), do: ctx |> generate_conn(attrs) |> json_response(201)

  defp generate_conn(ctx, attrs) do
    body =
      Map.merge(
        %{batch_no: "LOT-API-1", production_date: "2026-11-20", expiry_date: "2027-11-20"},
        attrs
      )

    ctx.user
    |> auth()
    |> post(~p"/api/v1/manufacturer/products/#{ctx.product.id}/serials", Jason.encode!(body))
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
