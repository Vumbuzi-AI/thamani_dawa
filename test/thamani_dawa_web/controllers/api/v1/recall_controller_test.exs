defmodule ThamaniDawaWeb.Api.V1.RecallControllerTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.SitesFixtures

  alias ThamaniDawa.Recalls

  setup do
    admin = user_fixture()
    pharmacy = site_fixture(%{organization_id: admin.organization_id, activities: [:pharmacy]})

    pharmacist =
      staff_fixture(%{
        organization_id: admin.organization_id,
        invited_by_id: admin.id,
        site_id: pharmacy.id,
        role: :pharmacist
      })

    batch = batch_fixture(%{organization_id: admin.organization_id, site_id: pharmacy.id})
    other_batch = batch_fixture(%{gtin: batch.gtin, batch_no: batch.batch_no})

    {:ok, recall} =
      Recalls.initiate_recall(
        batch.gtin,
        batch.batch_no,
        "INC-API-1",
        :class_ii,
        "Contamination",
        superadmin_fixture()
      )

    {:ok,
     admin: admin, pharmacist: pharmacist, batch: batch, other_batch: other_batch, recall: recall}
  end

  test "an admin sees only their own organization's recalled batches", ctx do
    body = ctx.admin |> auth() |> get(~p"/api/v1/org/recalls?status=open") |> json_response(200)

    assert [holder] = body["data"]
    assert holder["batch_id"] == ctx.batch.id
    assert holder["acknowledged_at"] == nil
    assert holder["recall"]["reference"] == "INC-API-1"
    assert holder["recall"]["classification"] == "class_ii"
    assert holder["batch"]["status"] == "recalled"

    closed =
      ctx.admin |> auth() |> get(~p"/api/v1/org/recalls?status=closed") |> json_response(200)

    assert closed["data"] == []
  end

  test "an admin acknowledges their holder", ctx do
    [holder] =
      ctx.admin
      |> auth()
      |> get(~p"/api/v1/org/recalls")
      |> json_response(200)
      |> Map.fetch!("data")

    body =
      ctx.admin
      |> auth()
      |> post(~p"/api/v1/org/recalls/holders/#{holder["id"]}/acknowledge")
      |> json_response(200)

    assert body["data"]["acknowledged_at"]
    assert body["data"]["acknowledged_by_id"] == ctx.admin.id
  end

  test "another organization's holder cannot be acknowledged", ctx do
    foreign =
      ctx.recall.id
      |> Recalls.get_recall!()
      |> Map.fetch!(:holders)
      |> Enum.find(&(&1.batch_id == ctx.other_batch.id))

    conn = ctx.admin |> auth() |> post(~p"/api/v1/org/recalls/holders/#{foreign.id}/acknowledge")
    assert json_response(conn, 403)["error"]["code"] == "forbidden"

    missing = ctx.admin |> auth() |> post(~p"/api/v1/org/recalls/holders/0/acknowledge")
    assert json_response(missing, 404)["error"]["code"] == "not_found"
  end

  test "site staff cannot acknowledge recalls", ctx do
    conn = ctx.pharmacist |> auth() |> get(~p"/api/v1/org/recalls")
    assert json_response(conn, 403)["error"]["code"] == "forbidden"
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
