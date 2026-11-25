defmodule ThamaniDawaWeb.Api.V1.DistributorControllerTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.DistributorFixtures
  import ThamaniDawa.ProductsFixtures

  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.GoodsReceipts
  alias ThamaniDawa.GoodsReceipts.GoodsReceipt
  alias ThamaniDawa.Repo

  setup do
    organization = distributor_organization_fixture()
    warehouse = warehouse_fixture(organization.id)

    user =
      distributor_user_fixture(%{organization_id: organization.id, site_id: warehouse.id})

    product = product_fixture(%{organization_id: organization.id})
    {:ok, organization: organization, warehouse: warehouse, user: user, product: product}
  end

  test "only distributor staff get in" do
    pharmacist = staff_fixture()

    body =
      pharmacist
      |> auth()
      |> get(~p"/api/v1/distributor/customers")
      |> json_response(403)

    assert body["error"]["code"]
  end

  test "creates, lists and updates customers", ctx do
    created =
      ctx.user
      |> auth()
      |> post(
        ~p"/api/v1/distributor/customers",
        Jason.encode!(%{name: "Mji Pharmacy", customer_type: "pharmacy"})
      )
      |> json_response(201)

    assert created["data"]["name"] == "Mji Pharmacy"

    listed = ctx.user |> auth() |> get(~p"/api/v1/distributor/customers") |> json_response(200)
    assert Enum.map(listed["data"], & &1["id"]) == [created["data"]["id"]]

    updated =
      ctx.user
      |> auth()
      |> patch(
        ~p"/api/v1/distributor/customers/#{created["data"]["id"]}",
        Jason.encode!(%{contact_phone: "0700000000"})
      )
      |> json_response(200)

    assert updated["data"]["contact_phone"] == "0700000000"

    invalid =
      ctx.user
      |> auth()
      |> post(~p"/api/v1/distributor/customers", Jason.encode!(%{customer_type: "bakery"}))
      |> json_response(422)

    assert invalid["error"]["fields"]["name"]
  end

  test "a customer return goes from draft to completed and puts stock away", ctx do
    customer = customer(ctx)

    draft =
      ctx.user
      |> auth()
      |> post(
        ~p"/api/v1/distributor/customer-returns",
        Jason.encode!(%{customer_id: customer.id, reason: "overstock"})
      )
      |> json_response(201)

    # Staff stationed at a warehouse return stock to that warehouse.
    assert draft["data"]["site_id"] == ctx.warehouse.id
    id = draft["data"]["id"]

    empty =
      ctx.user |> auth() |> post(~p"/api/v1/distributor/customer-returns/#{id}/receive")

    assert json_response(empty, 422)["error"]["code"] == "no_items"

    with_item =
      ctx.user
      |> auth()
      |> post(
        ~p"/api/v1/distributor/customer-returns/#{id}/items",
        Jason.encode!(%{
          product_id: ctx.product.id,
          quantity: 4,
          batch_no: "RET-1",
          expiry_date: Date.to_iso8601(Date.add(Date.utc_today(), 200))
        })
      )
      |> json_response(201)

    [item] = with_item["data"]["items"]

    early =
      ctx.user
      |> auth()
      |> post(~p"/api/v1/distributor/customer-returns/#{id}/complete")
      |> json_response(409)

    assert early["error"]["code"] == "not_inspected"

    received =
      ctx.user
      |> auth()
      |> post(~p"/api/v1/distributor/customer-returns/#{id}/receive")
      |> json_response(200)

    assert received["data"]["status"] == "received"

    not_yet =
      ctx.user
      |> auth()
      |> post(~p"/api/v1/distributor/customer-returns/#{id}/inspect")
      |> json_response(422)

    assert not_yet["error"]["code"] == "items_not_inspected"

    ctx.user
    |> auth()
    |> put(
      ~p"/api/v1/distributor/customer-returns/#{id}/items/#{item["id"]}",
      Jason.encode!(%{condition: "sellable"})
    )
    |> json_response(200)

    ctx.user
    |> auth()
    |> post(~p"/api/v1/distributor/customer-returns/#{id}/inspect")
    |> json_response(200)

    completed =
      ctx.user
      |> auth()
      |> post(~p"/api/v1/distributor/customer-returns/#{id}/complete")
      |> json_response(200)

    assert completed["data"]["status"] == "completed"
    [done] = completed["data"]["items"]
    batch = Repo.get!(Batch, done["batch_id"])
    assert batch.site_id == ctx.warehouse.id
    assert batch.remaining_quantity == 4
    assert batch.status == :active
  end

  test "a return refuses a product or customer from another organization", ctx do
    other = product_fixture()

    missing_customer =
      ctx.user
      |> auth()
      |> post(~p"/api/v1/distributor/customer-returns", Jason.encode!(%{customer_id: 999_999}))

    assert json_response(missing_customer, 404)

    draft =
      ctx.user
      |> auth()
      |> post(
        ~p"/api/v1/distributor/customer-returns",
        Jason.encode!(%{customer_id: customer(ctx).id})
      )
      |> json_response(201)

    foreign =
      ctx.user
      |> auth()
      |> post(
        ~p"/api/v1/distributor/customer-returns/#{draft["data"]["id"]}/items",
        Jason.encode!(%{
          product_id: other.id,
          quantity: 1,
          batch_no: "X",
          expiry_date: "2030-01-01"
        })
      )

    assert json_response(foreign, 404)
  end

  test "lists receipts and resolves a receiving discrepancy", ctx do
    {:ok, receipt} =
      %GoodsReceipt{organization_id: ctx.organization.id}
      |> GoodsReceipt.changeset(%{
        number: "GRN-#{System.unique_integer([:positive])}",
        posting_key: Ecto.UUID.generate(),
        received_at: DateTime.utc_now(:second),
        received_by_id: ctx.user.id
      })
      |> Repo.insert()

    discrepancy =
      GoodsReceipts.create_discrepancy!(ctx.organization.id, receipt.id, %{
        "quantity" => 2,
        "site_id" => ctx.warehouse.id,
        "product_id" => ctx.product.id,
        "gtin" => ctx.product.gtin,
        "batch_no" => "LOT-9"
      })

    receipts =
      ctx.user |> auth() |> get(~p"/api/v1/distributor/receipts") |> json_response(200)

    assert Enum.map(receipts["data"], & &1["id"]) == [receipt.id]

    shown =
      ctx.user
      |> auth()
      |> get(~p"/api/v1/distributor/receipts/#{receipt.id}")
      |> json_response(200)

    assert [%{"status" => "open"}] = shown["data"]["discrepancies"]

    open =
      ctx.user |> auth() |> get(~p"/api/v1/distributor/discrepancies") |> json_response(200)

    assert Enum.map(open["data"], & &1["id"]) == [discrepancy.id]

    no_reference =
      ctx.user
      |> auth()
      |> post(
        ~p"/api/v1/distributor/discrepancies/#{discrepancy.id}/resolve",
        Jason.encode!(%{status: "lost"})
      )
      |> json_response(422)

    assert no_reference["error"]["fields"]["resolution_reference"]

    found =
      ctx.user
      |> auth()
      |> post(
        ~p"/api/v1/distributor/discrepancies/#{discrepancy.id}/resolve",
        Jason.encode!(%{status: "found"})
      )
      |> json_response(200)

    assert found["data"]["status"] == "found"

    again =
      ctx.user
      |> auth()
      |> post(
        ~p"/api/v1/distributor/discrepancies/#{discrepancy.id}/resolve",
        Jason.encode!(%{status: "found"})
      )
      |> json_response(409)

    assert again["error"]["code"] == "already_resolved"
  end

  defp customer(ctx) do
    {:ok, customer} =
      ThamaniDawa.Customers.create_customer(ctx.organization.id, %{
        "name" => "Customer #{System.unique_integer([:positive])}",
        "customer_type" => "pharmacy"
      })

    customer
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
