defmodule ThamaniDawaWeb.OrgReceivingLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures, only: [unique_gtin: 0]
  import ThamaniDawa.DistributorFixtures

  alias ThamaniDawa.Batches
  alias ThamaniDawa.GoodsReceipts
  alias ThamaniDawa.ProductsFixtures
  alias ThamaniDawa.SuppliersFixtures

  setup %{conn: conn} do
    organization = distributor_organization_fixture()
    admin = staff_fixture(%{organization_id: organization.id, role: :admin})
    %{conn: log_in_user(conn, admin), organization: organization}
  end

  test "unknown GTIN opens inline product setup", %{conn: conn} do
    gtin = unique_gtin()
    {:ok, view, _html} = live(conn, ~p"/org/receiving/new")

    view
    |> form("#distributor-scan-gtin-form", scan: %{gtin: gtin})
    |> render_change()

    assert has_element?(view, "#distributor-new-product-form")

    assert has_element?(
             view,
             "#distributor-new-product-form input[name='product[gtin]'][value='#{gtin}']"
           )
  end

  test "admin receives multiple lines atomically into organization stock", %{
    conn: conn,
    organization: organization
  } do
    product = ProductsFixtures.product_fixture(%{organization_id: organization.id, uom: "U2"})
    supplier = SuppliersFixtures.supplier_fixture(%{organization_id: organization.id})
    {:ok, view, _html} = live(conn, ~p"/org/receiving/new")

    add_line(view, product.gtin, "ORG-LOT-1", 20, supplier.id)
    add_line(view, product.gtin, "ORG-LOT-2", 10, supplier.id)

    assert has_element?(view, "#finish-distributor-delivery", "2 items")
    view |> element("#finish-distributor-delivery") |> render_click()

    assert_patch(view, ~p"/org/receiving")
    assert [receipt] = GoodsReceipts.list_receipts(organization.id)
    assert length(receipt.items) == 2
    assert Enum.all?(receipt.items, &is_nil(&1.site_id))

    assert organization.id
           |> Batches.list_undispatched_batches_for_product(product.id)
           |> Enum.map(& &1.batch_no)
           |> Enum.sort() == ["ORG-LOT-1", "ORG-LOT-2"]
  end

  test "non-admin distributor cannot enter the organization receiving route", %{
    organization: organization
  } do
    distributor = distributor_user_fixture(%{organization_id: organization.id})

    assert {:error, {:redirect, %{to: "/"}}} =
             live(log_in_user(build_conn(), distributor), ~p"/org/receiving")
  end

  defp add_line(view, gtin, batch_no, quantity, supplier_id) do
    view
    |> form("#distributor-scan-gtin-form", scan: %{gtin: gtin})
    |> render_change()

    view
    |> form("#distributor-receipt-form",
      batch: %{
        batch_no: batch_no,
        supplier_id: Integer.to_string(supplier_id),
        expiry_date: Date.utc_today() |> Date.add(365) |> Date.to_iso8601(),
        quantity: Integer.to_string(quantity)
      }
    )
    |> render_submit()
  end
end
