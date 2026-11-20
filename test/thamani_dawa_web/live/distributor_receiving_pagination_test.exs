defmodule ThamaniDawaWeb.DistributorReceivingPaginationTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.DistributorFixtures
  import ThamaniDawa.ProductsFixtures

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.GoodsReceipts.GoodsReceipt
  alias ThamaniDawa.Repo

  test "page 2 shows only its own rows, not page 1's too" do
    organization = distributor_organization_fixture()
    warehouse = warehouse_fixture(organization.id)

    admin =
      staff_fixture(%{
        organization_id: organization.id,
        role: :distributor,
        site_id: warehouse.id
      })

    product = product_fixture(%{organization_id: organization.id})

    {:ok, admin} = ThamaniDawa.Accounts.switch_current_site(Scope.for_user(admin), warehouse.id)

    for n <- 1..12 do
      {:ok, receipt} =
        %GoodsReceipt{}
        |> GoodsReceipt.changeset(%{
          number: "GRN-#{String.pad_leading(Integer.to_string(n), 6, "0")}",
          posting_key: Ecto.UUID.generate(),
          received_at:
            DateTime.utc_now() |> DateTime.add(n, :minute) |> DateTime.truncate(:second),
          received_by_id: admin.id
        })
        |> Ecto.Changeset.put_change(:organization_id, organization.id)
        |> Repo.insert()

      {:ok, _batch} =
        ThamaniDawa.Batches.create_batch(organization.id, %{
          "product_id" => product.id,
          "site_id" => warehouse.id,
          "gtin" => product.gtin,
          "batch_no" => "LOT-#{n}",
          "expiry_date" => Date.add(Date.utc_today(), 365),
          "quantity" => 10,
          "remaining_quantity" => 10,
          "goods_receipt_id" => receipt.id
        })
    end

    conn = log_in_user(build_conn(), admin)

    {:ok, view, _html} = live(conn, ~p"/distributor/receiving")

    assert view |> element("#distributor-receipts") |> render() =~ "GRN-000012"
    refute view |> element("#distributor-receipts") |> render() =~ "GRN-000001"

    {:error, {:live_redirect, %{to: to}}} =
      view
      |> element("a", "2")
      |> render_click()

    {:ok, view, _html} = live(conn, to)

    html = view |> element("#distributor-receipts") |> render()
    grn_count = html |> String.split("GRN-0000") |> length() |> Kernel.-(1)

    assert grn_count == 2, "expected 2 rows on page 2, got #{grn_count}"
    assert html =~ "GRN-000002"
    assert html =~ "GRN-000001"
    refute html =~ "GRN-000012"
  end
end
