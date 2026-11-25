defmodule ThamaniDawaWeb.Api.V1.PharmacyControllerTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.SitesFixtures

  setup do
    admin = user_fixture()
    pharmacy = site_fixture(%{organization_id: admin.organization_id, activities: [:pharmacy]})
    lab = site_fixture(%{organization_id: admin.organization_id, activities: [:laboratory]})

    pharmacist =
      staff_fixture(%{
        organization_id: admin.organization_id,
        invited_by_id: admin.id,
        site_id: pharmacy.id,
        role: :pharmacist
      })

    unassigned =
      staff_fixture(%{
        organization_id: admin.organization_id,
        invited_by_id: admin.id,
        role: :pharmacist
      })

    technician =
      staff_fixture(%{
        organization_id: admin.organization_id,
        invited_by_id: admin.id,
        site_id: lab.id,
        role: :lab_technician
      })

    {:ok,
     pharmacy: pharmacy, pharmacist: pharmacist, unassigned: unassigned, technician: technician}
  end

  test "a pharmacist scan of approved stock is found", %{
    pharmacy: pharmacy,
    pharmacist: pharmacist
  } do
    batch = batch_fixture(%{organization_id: pharmacist.organization_id, site_id: pharmacy.id})

    conn = post(auth(pharmacist), ~p"/api/v1/pharmacy/scans", %{raw: batch.gtin})
    body = json_response(conn, 200)

    assert body["data"]["state"] == "found"
    assert Enum.any?(body["data"]["batches"], &(&1["id"] == batch.id))
  end

  test "a lab technician cannot open the pharmacy counter", %{technician: technician} do
    conn = post(auth(technician), ~p"/api/v1/pharmacy/scans", %{raw: "01234567890128"})

    assert json_response(conn, 403)["error"]["code"] == "forbidden"
  end

  test "a pharmacist with no current site must choose one", %{unassigned: unassigned} do
    conn = post(auth(unassigned), ~p"/api/v1/pharmacy/scans", %{raw: "01234567890128"})

    assert json_response(conn, 422)["error"]["code"] == "site_required"
  end

  describe "stock lists show usable stock only" do
    setup %{pharmacy: pharmacy, pharmacist: pharmacist} do
      org_id = pharmacist.organization_id
      product = ThamaniDawa.ProductsFixtures.product_fixture(%{organization_id: org_id})

      usable =
        batch_fixture(%{organization_id: org_id, site_id: pharmacy.id, product_id: product.id})

      hidden =
        for status <- [:disaggregated, :returned, :expired] do
          %{organization_id: org_id, site_id: pharmacy.id, product_id: product.id}
          |> batch_fixture()
          |> Ecto.Changeset.change(status: status)
          |> ThamaniDawa.Repo.update!()
        end

      past_date =
        %{organization_id: org_id, site_id: pharmacy.id, product_id: product.id}
        |> batch_fixture()
        |> Ecto.Changeset.change(expiry_date: Date.add(Date.utc_today(), -5))
        |> ThamaniDawa.Repo.update!()

      only_unusable = ThamaniDawa.ProductsFixtures.product_fixture(%{organization_id: org_id})

      %{organization_id: org_id, site_id: pharmacy.id, product_id: only_unusable.id}
      |> batch_fixture()
      |> Ecto.Changeset.change(status: :disaggregated)
      |> ThamaniDawa.Repo.update!()

      {:ok,
       product: product,
       usable: usable,
       hidden: [past_date | hidden],
       only_unusable: only_unusable}
    end

    test "a product's batches leave out split, returned and expired lots", ctx do
      body =
        ctx.pharmacist
        |> auth()
        |> get(~p"/api/v1/pharmacy/stock/products/#{ctx.product.id}")
        |> json_response(200)

      assert Enum.map(body["data"]["batches"], & &1["id"]) == [ctx.usable.id]
    end

    test "the stock list leaves out products with no usable batch", ctx do
      body = ctx.pharmacist |> auth() |> get(~p"/api/v1/pharmacy/stock") |> json_response(200)
      ids = Enum.map(body["data"], & &1["id"])

      assert ctx.product.id in ids
      refute ctx.only_unusable.id in ids
    end
  end

  defp auth(user) do
    conn =
      post(build_conn(), ~p"/api/v1/login", %{email: user.email, password: valid_user_password()})

    token = json_response(conn, 200)["access_token"]

    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("content-type", "application/json")
  end
end
