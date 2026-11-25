defmodule ThamaniDawaWeb.Api.V1.StockTakeControllerTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures

  alias ThamaniDawa.Batches

  setup do
    admin = user_fixture()
    org_id = admin.organization_id
    pharmacy = site_fixture(%{organization_id: org_id, activities: [:pharmacy]})
    lab = site_fixture(%{organization_id: org_id, activities: [:laboratory]})

    pharmacist =
      staff_fixture(%{
        organization_id: org_id,
        invited_by_id: admin.id,
        site_id: pharmacy.id,
        role: :pharmacist
      })

    technician =
      staff_fixture(%{
        organization_id: org_id,
        invited_by_id: admin.id,
        site_id: lab.id,
        role: :lab_technician
      })

    batch = batch_fixture(%{organization_id: org_id, site_id: pharmacy.id, quantity: 20})

    consumable = product_fixture(%{organization_id: org_id, inventory_type: :lab_consumable})

    lab_batch =
      batch_fixture(%{organization_id: org_id, site_id: lab.id, product_id: consumable.id})

    {:ok,
     admin: admin,
     pharmacy: pharmacy,
     pharmacist: pharmacist,
     technician: technician,
     batch: batch,
     lab_batch: lab_batch}
  end

  test "a pharmacist counts, submits, and an admin approves", ctx do
    created =
      ctx.pharmacist
      |> auth()
      |> post(~p"/api/v1/pharmacy/stock-takes", Jason.encode!(%{notes: "Monthly"}))
      |> json_response(201)
      |> Map.fetch!("data")

    assert created["status"] == "draft"
    assert created["site_id"] == ctx.pharmacy.id
    assert created["inventory_type"] == "medicine"
    assert [item] = created["items"]
    assert item["batch_id"] == ctx.batch.id
    assert item["expected_quantity"] == 20

    counted =
      ctx.pharmacist
      |> auth()
      |> put(
        ~p"/api/v1/pharmacy/stock-takes/#{created["id"]}/items/#{item["id"]}",
        Jason.encode!(%{counted_quantity: 17})
      )
      |> json_response(200)
      |> Map.fetch!("data")

    assert [%{"counted_quantity" => 17, "variance" => -3}] = counted["items"]

    submitted =
      ctx.pharmacist
      |> auth()
      |> post(~p"/api/v1/pharmacy/stock-takes/#{created["id"]}/submit")
      |> json_response(200)

    assert submitted["data"]["status"] == "pending"

    queue =
      ctx.admin |> auth() |> get(~p"/api/v1/org/stock-takes?status=pending") |> json_response(200)

    assert Enum.map(queue["data"], & &1["id"]) == [created["id"]]
    assert queue["meta"]["tab_counts"]["pending"] == 1

    approved =
      ctx.admin
      |> auth()
      |> post(~p"/api/v1/org/stock-takes/#{created["id"]}/approve")
      |> json_response(200)

    assert approved["data"]["status"] == "approved"
    assert approved["data"]["approved_by_id"] == ctx.admin.id
    assert Batches.get_batch!(ctx.admin.organization_id, ctx.batch.id).remaining_quantity == 17
  end

  test "only admins approve or reject", ctx do
    stock_take = create_stock_take(ctx.pharmacist)

    for path <- [
          ~p"/api/v1/org/stock-takes/#{stock_take["id"]}/approve",
          ~p"/api/v1/org/stock-takes/#{stock_take["id"]}/reject"
        ] do
      conn = ctx.pharmacist |> auth() |> post(path, Jason.encode!(%{rejection_reason: "no"}))
      assert json_response(conn, 403)["error"]["code"] == "forbidden"
    end
  end

  test "an admin rejects a pending stock take with a reason", ctx do
    stock_take = create_stock_take(ctx.pharmacist)
    item = hd(stock_take["items"])

    ctx.pharmacist
    |> auth()
    |> put(
      ~p"/api/v1/pharmacy/stock-takes/#{stock_take["id"]}/items/#{item["id"]}",
      Jason.encode!(%{counted_quantity: 5})
    )
    |> json_response(200)

    ctx.pharmacist
    |> auth()
    |> post(~p"/api/v1/pharmacy/stock-takes/#{stock_take["id"]}/submit")
    |> json_response(200)

    rejected =
      ctx.admin
      |> auth()
      |> post(
        ~p"/api/v1/org/stock-takes/#{stock_take["id"]}/reject",
        Jason.encode!(%{rejection_reason: "Recount the shelf"})
      )
      |> json_response(200)

    assert rejected["data"]["status"] == "rejected"
    assert rejected["data"]["rejection_reason"] == "Recount the shelf"
    assert Batches.get_batch!(ctx.admin.organization_id, ctx.batch.id).remaining_quantity == 20
  end

  test "submitting with nothing counted is a clear 422", ctx do
    stock_take = create_stock_take(ctx.pharmacist)

    conn =
      ctx.pharmacist
      |> auth()
      |> post(~p"/api/v1/pharmacy/stock-takes/#{stock_take["id"]}/submit")

    assert json_response(conn, 422)["error"]["code"] == "no_counted_items"
  end

  test "a negative count is a field error", ctx do
    stock_take = create_stock_take(ctx.pharmacist)
    item = hd(stock_take["items"])

    conn =
      ctx.pharmacist
      |> auth()
      |> put(
        ~p"/api/v1/pharmacy/stock-takes/#{stock_take["id"]}/items/#{item["id"]}",
        Jason.encode!(%{counted_quantity: -1})
      )

    assert json_response(conn, 422)["error"]["fields"]["counted_quantity"]
  end

  test "lists only this site's stock takes", ctx do
    stock_take = create_stock_take(ctx.pharmacist)

    body = ctx.pharmacist |> auth() |> get(~p"/api/v1/pharmacy/stock-takes") |> json_response(200)
    assert Enum.map(body["data"], & &1["id"]) == [stock_take["id"]]
    assert body["meta"]["total"] == 1
  end

  test "a batch from another site cannot be added", ctx do
    stock_take = create_stock_take(ctx.pharmacist)
    elsewhere = batch_fixture(%{organization_id: ctx.admin.organization_id})

    conn =
      ctx.pharmacist
      |> auth()
      |> post(
        ~p"/api/v1/pharmacy/stock-takes/#{stock_take["id"]}/items",
        Jason.encode!(%{batch_id: elsewhere.id})
      )

    assert json_response(conn, 404)["error"]["code"] == "not_found"
  end

  test "the lab counts lab consumables at its own site", ctx do
    created =
      ctx.technician
      |> auth()
      |> post(~p"/api/v1/lab/stock-takes", Jason.encode!(%{}))
      |> json_response(201)
      |> Map.fetch!("data")

    assert created["inventory_type"] == "lab_consumable"
    assert Enum.map(created["items"], & &1["batch_id"]) == [ctx.lab_batch.id]

    conn = ctx.technician |> auth() |> get(~p"/api/v1/pharmacy/stock-takes")
    assert json_response(conn, 403)["error"]["code"] == "forbidden"
  end

  test "an admin with no current site must pick one for site routes", ctx do
    stock_take = create_stock_take(ctx.pharmacist)
    conn = ctx.admin |> auth() |> get(~p"/api/v1/lab/stock-takes/#{stock_take["id"]}")

    assert json_response(conn, 422)["error"]["code"] == "site_required"
  end

  defp create_stock_take(user) do
    user
    |> auth()
    |> post(~p"/api/v1/pharmacy/stock-takes", Jason.encode!(%{}))
    |> json_response(201)
    |> Map.fetch!("data")
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
