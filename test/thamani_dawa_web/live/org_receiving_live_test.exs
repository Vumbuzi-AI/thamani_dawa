defmodule ThamaniDawaWeb.OrgReceivingLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures, only: [unique_gtin: 0]
  import ThamaniDawa.DistributorFixtures
  import ThamaniDawa.OrganizationsFixtures

  alias ThamaniDawa.Batches
  alias ThamaniDawa.GoodsReceipts
  alias ThamaniDawa.ProductsFixtures
  alias ThamaniDawa.SuppliersFixtures

  @valid_sscc "006141411234567890"

  # A non-distributor org — the supplier-based org-pool receiving flow
  # exercised here no longer applies to distributor orgs, which always use
  # the live GLN-to-GLN origin flow on `/org/receiving` too (see
  # `ThamaniDawaWeb.DistributorReceivingLive`).
  setup %{conn: conn} do
    organization = organization_fixture()
    admin = staff_fixture(%{organization_id: organization.id, role: :admin})
    %{conn: log_in_user(conn, admin), organization: organization}
  end

  test "unknown GTIN opens inline product setup", %{conn: conn} do
    gtin = unique_gtin()
    {:ok, view, _html} = live(conn, ~p"/org/receiving/new")

    open_add_item(view)

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

  test "item form omits serial and requires a case-label SSCC", %{
    conn: conn,
    organization: organization
  } do
    product = ProductsFixtures.product_fixture(%{organization_id: organization.id})
    {:ok, view, _html} = live(conn, ~p"/org/receiving/new")

    open_add_item(view)

    view
    |> form("#distributor-scan-gtin-form", scan: %{gtin: product.gtin})
    |> render_change()

    refute has_element?(view, "#distributor-receipt-form input[name='batch[serial]']")
    assert has_element?(view, "#distributor-receipt-form input[name='batch[sscc]'][required]")
    refute render(view) =~ "Leave blank if the delivery has no case/pallet label"
  end

  test "non-admin distributor cannot enter the organization receiving route", %{
    organization: organization
  } do
    distributor = distributor_user_fixture(%{organization_id: organization.id})

    assert {:error, {:redirect, %{to: "/"}}} =
             live(log_in_user(build_conn(), distributor), ~p"/org/receiving")
  end

  defp add_line(view, gtin, batch_no, quantity, supplier_id) do
    open_add_item(view)

    view
    |> form("#distributor-scan-gtin-form", scan: %{gtin: gtin})
    |> render_change()

    view
    |> form("#distributor-receipt-form",
      batch: %{
        batch_no: batch_no,
        supplier_id: Integer.to_string(supplier_id),
        expiry_date: Date.utc_today() |> Date.add(365) |> Date.to_iso8601(),
        quantity: Integer.to_string(quantity),
        sscc: @valid_sscc
      }
    )
    |> render_submit()
  end

  # The receiving screen keeps the scan form behind the "Add item" modal,
  # triggered from either the empty-state button or the one above the
  # table once items exist.
  defp open_add_item(view) do
    if has_element?(view, "#open-add-item-empty") do
      view |> element("#open-add-item-empty") |> render_click()
    else
      view |> element("#open-add-item-bottom") |> render_click()
    end
  end
end
