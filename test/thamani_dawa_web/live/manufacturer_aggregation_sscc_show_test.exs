defmodule ThamaniDawaWeb.ManufacturerAggregationSsccShowTest do
  use ThamaniDawaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ThamaniDawa.ManufacturerFixtures

  alias ThamaniDawa.Manufacturing

  setup %{conn: conn} do
    organization = manufacturer_organization_fixture()
    site = manufacturing_site_fixture(organization.id)
    user = manufacturer_user_fixture(%{organization_id: organization.id, site_id: site.id})

    %{conn: log_in_user(conn, user), organization: organization}
  end

  test "shows packed contents without manual editing controls", %{
    conn: conn,
    organization: organization
  } do
    shipper = pallet_ready_shipper_fixture(organization.id)
    product = manufacturer_product_fixture(organization.id)
    batch = manufacturer_batch_fixture(organization.id, product.id)

    {:ok, _batch} = Manufacturing.add_batch_to_sscc(organization.id, shipper.id, batch.id)

    {:ok, _serial} =
      Manufacturing.create_manual_serial(organization.id, batch, shipper, %{
        "serial" => "SER-SSCC-1"
      })

    {:ok, view, _html} = live(conn, ~p"/manufacturer/aggregations/ssccs/#{shipper.id}")

    assert has_element?(view, "#sscc-contents")
    assert has_element?(view, "#sscc-batch-#{batch.id}", "1 serials")
    assert has_element?(view, "h1", "Shipper #{shipper.code}")
    assert has_element?(view, "#add-sscc-gtin", "Add GTIN")
    assert has_element?(view, "#upload-sscc-gtins", "Upload GTINs")
    assert has_element?(view, "#add-sscc-batch", "Add batch")
    assert has_element?(view, "#add-sscc-serials", "Add serials")
  end

  test "empty shipper shows an empty state instead of manual entry forms", %{
    conn: conn,
    organization: organization
  } do
    shipper = pallet_ready_shipper_fixture(organization.id)

    {:ok, view, _html} = live(conn, ~p"/manufacturer/aggregations/ssccs/#{shipper.id}")

    assert has_element?(view, "#sscc-contents", "No GTINs or batches on this SSCC yet")
    assert has_element?(view, "#add-sscc-gtin", "Add GTIN")
    refute has_element?(view, "#sscc-gtin-modal")
    refute has_element?(view, "#sscc-serials-modal")
  end
end
