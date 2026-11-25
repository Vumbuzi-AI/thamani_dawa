defmodule ThamaniDawaWeb.Api.V1.CatalogControllerTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.DistributorFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures

  alias ThamaniDawa.Epcis.Outbox

  setup do
    organization = distributor_organization_fixture()
    admin = user_fixture(%{organization_id: organization.id})
    pharmacy = site_fixture(%{organization_id: organization.id, activities: [:pharmacy]})
    other_pharmacy = site_fixture(%{organization_id: organization.id, activities: [:pharmacy]})

    product =
      product_fixture(%{
        organization_id: organization.id,
        strength: "500mg",
        pack_uom: "box",
        units_per_pack: 10,
        net_content_quantity: 10,
        net_content_uom: "tablet"
      })

    pharmacist =
      staff_fixture(%{
        organization_id: organization.id,
        invited_by_id: admin.id,
        site_id: pharmacy.id,
        role: :pharmacist
      })

    {:ok,
     admin: admin,
     pharmacy: pharmacy,
     other_pharmacy: other_pharmacy,
     product: product,
     pharmacist: pharmacist}
  end

  describe "POST /api/v1/products/:id/batches" do
    test "receives a batch at the site, auto-approved, with an EPCIS facility receipt", ctx do
      conn =
        ctx.admin
        |> auth()
        |> post(
          ~p"/api/v1/products/#{ctx.product.id}/batches",
          Jason.encode!(%{
            site_id: ctx.pharmacy.id,
            gtin: unique_gtin(),
            batch_no: "API-1",
            expiry_date: "2030-01-01",
            quantity: 40
          })
        )

      batch = json_response(conn, 201)["data"]

      assert batch["site_id"] == ctx.pharmacy.id
      assert batch["approver_id"] == ctx.admin.id
      assert batch["received_at"]
      assert batch["remaining_quantity"] == 40
      assert batch["status"] == "active"
      assert batch["serials"] == []
      assert Map.has_key?(batch, "sscc")
      assert Map.has_key?(batch, "logistic_unit_id")

      assert Enum.any?(
               Outbox.list_events(ctx.admin.organization_id),
               &(&1.event_type == "receiving" and &1.source_id == batch["id"])
             )
    end

    test "accepts site_id sent as a string", ctx do
      conn =
        ctx.admin
        |> auth()
        |> post(
          ~p"/api/v1/products/#{ctx.product.id}/batches",
          Jason.encode!(%{
            site_id: Integer.to_string(ctx.pharmacy.id),
            gtin: unique_gtin(),
            batch_no: "API-2",
            expiry_date: "2030-01-01",
            quantity: 5
          })
        )

      assert json_response(conn, 201)["data"]["site_id"] == ctx.pharmacy.id
    end

    test "without site_id, a multi-site organization records warehouse stock", ctx do
      conn =
        ctx.admin
        |> auth()
        |> post(
          ~p"/api/v1/products/#{ctx.product.id}/batches",
          Jason.encode!(%{
            gtin: unique_gtin(),
            batch_no: "API-3",
            expiry_date: "2030-01-01",
            quantity: 5
          })
        )

      batch = json_response(conn, 201)["data"]
      assert batch["site_id"] == nil
      assert batch["approver_id"] == nil

      product =
        ctx.admin |> auth() |> get(~p"/api/v1/products/#{ctx.product.id}") |> json_response(200)

      assert Enum.map(product["data"]["undispatched"], & &1["id"]) == [batch["id"]]
    end

    test "without site_id, a single-site organization receives into its site" do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id, activities: [:pharmacy]})
      product = product_fixture(%{organization_id: admin.organization_id})

      conn =
        admin
        |> auth()
        |> post(
          ~p"/api/v1/products/#{product.id}/batches",
          Jason.encode!(%{
            gtin: unique_gtin(),
            batch_no: "API-7",
            expiry_date: "2030-01-01",
            quantity: 5
          })
        )

      batch = json_response(conn, 201)["data"]
      assert batch["site_id"] == site.id
      assert batch["approver_id"] == admin.id
    end

    test "with a site_id that is not a number is a clear 422", ctx do
      conn =
        ctx.admin
        |> auth()
        |> post(
          ~p"/api/v1/products/#{ctx.product.id}/batches",
          Jason.encode!(%{site_id: "main", batch_no: "API-4", quantity: 5})
        )

      assert json_response(conn, 422)["error"]["code"] == "invalid_site_id"
    end

    test "with another organization's site is a field error", ctx do
      foreign_site = site_fixture()

      conn =
        ctx.admin
        |> auth()
        |> post(
          ~p"/api/v1/products/#{ctx.product.id}/batches",
          Jason.encode!(%{
            site_id: foreign_site.id,
            gtin: unique_gtin(),
            batch_no: "API-5",
            expiry_date: "2030-01-01",
            quantity: 5
          })
        )

      error = json_response(conn, 422)["error"]
      assert error["code"] == "validation_failed"
      assert error["fields"]["site_id"]
    end

    test "is admin only", ctx do
      conn =
        ctx.pharmacist
        |> auth()
        |> post(
          ~p"/api/v1/products/#{ctx.product.id}/batches",
          Jason.encode!(%{site_id: ctx.pharmacy.id, batch_no: "API-6", quantity: 5})
        )

      assert json_response(conn, 403)["error"]["code"] == "forbidden"
    end
  end

  describe "GET /api/v1/products/:id" do
    test "returns the pack fields, batches and pending receipts", ctx do
      on_shelf =
        batch_fixture(%{
          organization_id: ctx.admin.organization_id,
          product_id: ctx.product.id,
          site_id: ctx.pharmacy.id
        })

      in_transit =
        batch_fixture(%{
          organization_id: ctx.admin.organization_id,
          product_id: ctx.product.id,
          site_id: ctx.other_pharmacy.id,
          pending: true
        })

      body =
        ctx.admin |> auth() |> get(~p"/api/v1/products/#{ctx.product.id}") |> json_response(200)

      data = body["data"]

      assert data["product"]["strength"] == "500mg"
      assert data["product"]["pack_uom"] == "box"
      assert data["product"]["units_per_pack"] == 10
      assert data["product"]["net_content_quantity"] == 10
      assert data["product"]["net_content_uom"] == "tablet"

      assert data["batches"] |> Enum.map(& &1["id"]) |> Enum.sort() ==
               Enum.sort([on_shelf.id, in_transit.id])

      assert Enum.map(data["pending_receipt"], & &1["id"]) == [in_transit.id]
      assert data["undispatched"] == []
    end
  end

  describe "POST /api/v1/batches/:id/dispatch" do
    setup ctx do
      batch =
        org_batch_fixture(%{
          organization_id: ctx.admin.organization_id,
          product_id: ctx.product.id,
          quantity: 30
        })

      {:ok, batch: batch}
    end

    test "dispatches part of warehouse stock to a site, awaiting receipt there", ctx do
      conn =
        ctx.admin
        |> auth()
        |> post(
          ~p"/api/v1/batches/#{ctx.batch.id}/dispatch",
          Jason.encode!(%{site_id: ctx.other_pharmacy.id, quantity: 12})
        )

      moved = json_response(conn, 201)["data"]
      assert moved["site_id"] == ctx.other_pharmacy.id
      assert moved["quantity"] == 12
      assert moved["source_batch_id"] == ctx.batch.id
      assert moved["received_at"] == nil

      source =
        ctx.admin |> auth() |> get(~p"/api/v1/batches/#{ctx.batch.id}") |> json_response(200)

      assert source["data"]["remaining_quantity"] == 18
    end

    test "a batch already at a site is a clear 422", ctx do
      site_batch =
        batch_fixture(%{
          organization_id: ctx.admin.organization_id,
          product_id: ctx.product.id,
          site_id: ctx.pharmacy.id
        })

      conn =
        ctx.admin
        |> auth()
        |> post(
          ~p"/api/v1/batches/#{site_batch.id}/dispatch",
          Jason.encode!(%{site_id: ctx.other_pharmacy.id, quantity: 1})
        )

      assert json_response(conn, 422)["error"]["code"] == "already_dispatched"
    end

    test "more than is left is insufficient stock", ctx do
      conn =
        ctx.admin
        |> auth()
        |> post(
          ~p"/api/v1/batches/#{ctx.batch.id}/dispatch",
          Jason.encode!(%{site_id: ctx.other_pharmacy.id, quantity: 31})
        )

      assert json_response(conn, 422)["error"]["code"] == "insufficient_stock"
    end

    test "without a quantity is a clear 422", ctx do
      conn =
        ctx.admin
        |> auth()
        |> post(
          ~p"/api/v1/batches/#{ctx.batch.id}/dispatch",
          Jason.encode!(%{site_id: ctx.other_pharmacy.id})
        )

      assert json_response(conn, 422)["error"]["code"] == "quantity_required"
    end

    test "without a site_id is a clear 422", ctx do
      conn =
        ctx.admin
        |> auth()
        |> post(~p"/api/v1/batches/#{ctx.batch.id}/dispatch", Jason.encode!(%{quantity: 1}))

      assert json_response(conn, 422)["error"]["code"] == "site_id_required"
    end

    test "to another organization's site is not found", ctx do
      conn =
        ctx.admin
        |> auth()
        |> post(
          ~p"/api/v1/batches/#{ctx.batch.id}/dispatch",
          Jason.encode!(%{site_id: site_fixture().id, quantity: 1})
        )

      assert json_response(conn, 404)["error"]["code"] == "not_found"
    end
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
