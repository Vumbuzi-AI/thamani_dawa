defmodule ThamaniDawaWeb.Api.V1.DisposalControllerTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.SitesFixtures
  import ThamaniDawa.SuppliersFixtures

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Repo

  setup do
    admin = user_fixture()
    org_id = admin.organization_id
    pharmacy = site_fixture(%{organization_id: org_id, activities: [:pharmacy]})
    supplier = supplier_fixture(%{organization_id: org_id})

    pharmacist =
      staff_fixture(%{
        organization_id: org_id,
        invited_by_id: admin.id,
        site_id: pharmacy.id,
        role: :pharmacist
      })

    # Batches must be in date when received, so backdate one afterwards.
    expired =
      %{organization_id: org_id, site_id: pharmacy.id, quantity: 8}
      |> batch_fixture()
      |> Ecto.Changeset.change(expiry_date: Date.add(Date.utc_today(), -10))
      |> Repo.update!()

    in_date =
      batch_fixture(%{
        organization_id: org_id,
        site_id: pharmacy.id,
        supplier_id: supplier.id,
        expiry_date: Date.add(Date.utc_today(), 300),
        quantity: 50
      })

    {:ok,
     admin: admin, pharmacy: pharmacy, pharmacist: pharmacist, expired: expired, in_date: in_date}
  end

  test "an expiry write-off: draft, add the whole lot, submit, admin approves", ctx do
    disposal = create(ctx.pharmacist, "expiry")
    assert disposal["kind"] == "expiry"
    assert disposal["items"] == []
    assert Enum.any?(disposal["addable_batches"], &(&1["id"] == ctx.expired.id))

    added =
      ctx.pharmacist
      |> auth()
      |> post(
        ~p"/api/v1/pharmacy/disposals/#{disposal["id"]}/items",
        Jason.encode!(%{batch_id: ctx.expired.id, quantity: 8})
      )
      |> json_response(201)

    assert [%{"batch_id" => batch_id, "quantity" => 8}] = added["data"]["items"]
    assert batch_id == ctx.expired.id

    ctx.pharmacist
    |> auth()
    |> post(~p"/api/v1/pharmacy/disposals/#{disposal["id"]}/submit")
    |> json_response(200)

    approved =
      ctx.admin
      |> auth()
      |> post(~p"/api/v1/org/disposals/#{disposal["id"]}/approve")
      |> json_response(200)

    assert approved["data"]["status"] == "approved"
    batch = Batches.get_batch!(ctx.admin.organization_id, ctx.expired.id)
    assert batch.remaining_quantity == 0
    assert batch.status == :expired
  end

  test "an expiry write-off rejects an in-date lot and a partial quantity", ctx do
    disposal = create(ctx.pharmacist, "expiry")

    not_expired =
      ctx.pharmacist
      |> auth()
      |> post(
        ~p"/api/v1/pharmacy/disposals/#{disposal["id"]}/items",
        Jason.encode!(%{batch_id: ctx.in_date.id, quantity: 50})
      )

    assert json_response(not_expired, 422)["error"]["code"] == "not_expired"

    partial =
      ctx.pharmacist
      |> auth()
      |> post(
        ~p"/api/v1/pharmacy/disposals/#{disposal["id"]}/items",
        Jason.encode!(%{batch_id: ctx.expired.id, quantity: 3})
      )

    assert json_response(partial, 422)["error"]["code"] == "partial_expiry"
  end

  test "a supplier return can take part of a lot", ctx do
    disposal = create(ctx.pharmacist, "returned")
    assert disposal["kind"] == "returned"

    ctx.pharmacist
    |> auth()
    |> post(
      ~p"/api/v1/pharmacy/disposals/#{disposal["id"]}/items",
      Jason.encode!(%{batch_id: ctx.in_date.id, quantity: 20})
    )
    |> json_response(201)

    ctx.pharmacist
    |> auth()
    |> post(~p"/api/v1/pharmacy/disposals/#{disposal["id"]}/submit")
    |> json_response(200)

    ctx.admin
    |> auth()
    |> post(~p"/api/v1/org/disposals/#{disposal["id"]}/approve")
    |> json_response(200)

    assert Batches.get_batch!(ctx.admin.organization_id, ctx.in_date.id).remaining_quantity == 30

    returned =
      ctx.pharmacist
      |> auth()
      |> get(~p"/api/v1/pharmacy/disposals?kind=returned")
      |> json_response(200)

    assert Enum.map(returned["data"], & &1["id"]) == [disposal["id"]]

    expiry = ctx.pharmacist |> auth() |> get(~p"/api/v1/pharmacy/disposals") |> json_response(200)
    assert expiry["data"] == []
  end

  test "a supplier return needs a batch with a supplier", ctx do
    disposal = create(ctx.pharmacist, "returned")

    conn =
      ctx.pharmacist
      |> auth()
      |> post(
        ~p"/api/v1/pharmacy/disposals/#{disposal["id"]}/items",
        Jason.encode!(%{batch_id: ctx.expired.id, quantity: 1})
      )

    assert json_response(conn, 422)["error"]["code"] == "no_supplier"
  end

  test "an item can be removed from a draft", ctx do
    disposal = create(ctx.pharmacist, "returned")

    added =
      ctx.pharmacist
      |> auth()
      |> post(
        ~p"/api/v1/pharmacy/disposals/#{disposal["id"]}/items",
        Jason.encode!(%{batch_id: ctx.in_date.id, quantity: 1})
      )
      |> json_response(201)

    [item] = added["data"]["items"]

    removed =
      ctx.pharmacist
      |> auth()
      |> delete(~p"/api/v1/pharmacy/disposals/#{disposal["id"]}/items/#{item["id"]}")
      |> json_response(200)

    assert removed["data"]["items"] == []
  end

  test "only admins approve or reject, and rejecting leaves stock alone", ctx do
    disposal = create(ctx.pharmacist, "expiry")

    ctx.pharmacist
    |> auth()
    |> post(
      ~p"/api/v1/pharmacy/disposals/#{disposal["id"]}/items",
      Jason.encode!(%{batch_id: ctx.expired.id, quantity: 8})
    )
    |> json_response(201)

    ctx.pharmacist
    |> auth()
    |> post(~p"/api/v1/pharmacy/disposals/#{disposal["id"]}/submit")
    |> json_response(200)

    forbidden =
      ctx.pharmacist |> auth() |> post(~p"/api/v1/org/disposals/#{disposal["id"]}/approve")

    assert json_response(forbidden, 403)["error"]["code"] == "forbidden"

    rejected =
      ctx.admin
      |> auth()
      |> post(
        ~p"/api/v1/org/disposals/#{disposal["id"]}/reject",
        Jason.encode!(%{rejection_reason: "Wrong lot"})
      )
      |> json_response(200)

    assert rejected["data"]["status"] == "rejected"
    assert Batches.get_batch!(ctx.admin.organization_id, ctx.expired.id).remaining_quantity == 8
  end

  test "an unknown kind is a field error", ctx do
    conn =
      ctx.pharmacist
      |> auth()
      |> post(~p"/api/v1/pharmacy/disposals", Jason.encode!(%{kind: "stolen"}))

    assert json_response(conn, 422)["error"]["fields"]["kind"]
  end

  defp create(user, kind) do
    user
    |> auth()
    |> post(~p"/api/v1/pharmacy/disposals", Jason.encode!(%{kind: kind, reason: "Test"}))
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
