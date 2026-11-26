defmodule ThamaniDawaWeb.ManufacturerInventoryLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.ManufacturerFixtures

  alias ThamaniDawa.Manufacturing

  setup %{conn: conn} do
    organization = manufacturer_organization_fixture()
    site = manufacturing_site_fixture(organization.id)
    user = manufacturer_user_fixture(%{organization_id: organization.id, site_id: site.id})
    %{conn: log_in_user(conn, user), organization: organization}
  end

  test "renders inventory summary and batch table without TrackIQ", %{
    conn: conn,
    organization: organization
  } do
    product =
      manufacturer_product_fixture(organization.id, %{name: "Amoxicillin", gtin: "12345678901234"})

    batch = manufacturer_batch_fixture(organization.id, product.id, %{batch_no: "BATCH-1"})

    {:ok, view, html} = live(conn, ~p"/manufacturer/inventory")

    assert has_element?(view, "#inventory-summary")
    assert has_element?(view, "#inventory-batches-tab.is-active")
    assert has_element?(view, "#inventory-batches-table")
    assert html =~ "Amoxicillin"
    assert html =~ "12345678901234"
    assert html =~ "BATCH-1"

    assert has_element?(
             view,
             "#inventory-batch-serials-#{batch.id}[href='/manufacturer/products/12345678901234/serials?batch=BATCH-1']",
             "BATCH-1"
           )

    refute html =~ "TrackIQ"
    refute html =~ "standalone"
  end

  test "searches and filters batches", %{conn: conn, organization: organization} do
    p1 =
      manufacturer_product_fixture(organization.id, %{name: "Paracetamol", gtin: "11111111111111"})

    p2 =
      manufacturer_product_fixture(organization.id, %{name: "Ibuprofen", gtin: "22222222222222"})

    b1 = manufacturer_batch_fixture(organization.id, p1.id, %{batch_no: "PARA-1"})
    _b2 = manufacturer_batch_fixture(organization.id, p2.id, %{batch_no: "IBU-1"})

    {:ok, view, _html} = live(conn, ~p"/manufacturer/inventory")

    view
    |> form("#inventory-search-form", search: "Para")
    |> render_change()

    assert_patch(view, ~p"/manufacturer/inventory?q=Para&tab=batches")
    assert has_element?(view, "#inventory-batch-#{b1.id}")
    refute has_element?(view, "#inventory-batches-table", "IBU-1")

    view
    |> element("#inventory-status-status-ready_to_pack")
    |> render_click()

    assert_patch(view, ~p"/manufacturer/inventory?q=Para&status=ready_to_pack&tab=batches")
  end

  test "switches tabs and shows all shippers with Not on a pallet", %{
    conn: conn,
    organization: organization
  } do
    product = manufacturer_product_fixture(organization.id, %{name: "Cough Syrup"})
    batch = manufacturer_batch_fixture(organization.id, product.id, %{batch_no: "CS-1"})

    {:ok, shipper} =
      Manufacturing.create_manual_sscc(organization.id, nil, %{
        "code" => "100000000000000001",
        "gtin" => product.gtin,
        "batch" => batch.batch_no,
        "count_of_trade_items" => 10,
        "status" => "available"
      })

    {:ok, view, _html} = live(conn, ~p"/manufacturer/inventory")

    view |> element("#inventory-shippers-tab") |> render_click()
    assert_patch(view, ~p"/manufacturer/inventory?tab=shippers")
    html = render(view)

    assert has_element?(view, "#inventory-shippers-table")
    assert has_element?(view, "#inventory-shipper-detail-#{shipper.id}", shipper.code)
    assert html =~ shipper.code
    assert html =~ "Not on a pallet"
    refute html =~ "TrackIQ"
    refute html =~ "standalone"
  end

  test "shows pallet composition summary", %{conn: conn, organization: organization} do
    product = manufacturer_product_fixture(organization.id, %{name: "Tablet A"})
    batch = manufacturer_batch_fixture(organization.id, product.id, %{batch_no: "TAB-1"})

    {:ok, pallet} =
      Manufacturing.create_pallet(organization.id, %{
        "code" => "200000000000000001",
        "status" => "draft"
      })

    {:ok, shipper} =
      Manufacturing.create_manual_sscc(organization.id, pallet, %{
        "code" => "100000000000000002",
        "gtin" => product.gtin,
        "batch" => batch.batch_no,
        "count_of_trade_items" => 5,
        "status" => "available"
      })

    _ = Manufacturing.add_batch_to_sscc(organization.id, shipper.id, batch.id)

    {:ok, view, _html} = live(conn, ~p"/manufacturer/inventory?tab=pallets")

    html = render(view)
    assert has_element?(view, "#inventory-pallets-table")
    assert html =~ pallet.code
    assert html =~ "1 shipper"
    assert html =~ "1 product"
    assert html =~ "Batch TAB-1"
    refute html =~ "TrackIQ"
    refute html =~ "standalone"
  end

  test "sorts batches by newest by default and supports sort change", %{
    conn: conn,
    organization: organization
  } do
    product = manufacturer_product_fixture(organization.id)
    older = manufacturer_batch_fixture(organization.id, product.id, %{batch_no: "OLD-1"})
    newer = manufacturer_batch_fixture(organization.id, product.id, %{batch_no: "NEW-1"})

    {:ok, view, _html} = live(conn, ~p"/manufacturer/inventory")
    html = render(view)
    assert html =~ ~r/NEW-1.*OLD-1/s

    view |> element("#inventory-sort-sort-oldest") |> render_click()
    assert_patch(view, ~p"/manufacturer/inventory?sort=oldest&tab=batches")
    html = render(view)
    assert html =~ ~r/OLD-1.*NEW-1/s
    _ = older
    _ = newer
  end

  test "shows empty states for shippers and pallets", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/manufacturer/inventory?tab=shippers")
    assert render(view) =~ "No shippers yet"

    {:ok, view, _html} = live(conn, ~p"/manufacturer/inventory?tab=pallets")
    assert render(view) =~ "No pallets yet"
  end
end
