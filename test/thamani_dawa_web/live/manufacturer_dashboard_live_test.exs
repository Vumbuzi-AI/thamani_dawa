defmodule ThamaniDawaWeb.ManufacturerDashboardLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.ManufacturerFixtures

  defp manufacturer_conn(conn) do
    organization = manufacturer_organization_fixture()
    site = manufacturing_site_fixture(organization.id)
    user = manufacturer_user_fixture(%{organization_id: organization.id, site_id: site.id})
    %{conn: log_in_user(conn, user), organization: organization}
  end

  test "a new manufacturer sees the Doop dashboard recipe with empty states", %{conn: conn} do
    %{conn: conn} = manufacturer_conn(conn)

    {:ok, view, _html} = live(conn, ~p"/manufacturer")

    assert has_element?(view, "#manufacturer-dashboard .td-page-header", "Manufacturer dashboard")
    assert has_element?(view, "#manufacturer-glances .td-glance-cell", "0 GTINs registered")
    assert has_element?(view, "#stat-manufacturer-ssccs", "0 SSCCs issued")
    assert has_element?(view, "#manufacturer-no-serial-jobs")

    assert has_element?(
             view,
             "#manufacturer-aggregation-pipeline .td-status-row",
             "Open aggregations"
           )
  end

  test "recent serial jobs list the latest batches with a product link", %{conn: conn} do
    %{conn: conn, organization: organization} = manufacturer_conn(conn)
    product = manufacturer_product_fixture(organization.id)
    batch = manufacturer_batch_fixture(organization.id, product.id)

    {:ok, view, _html} = live(conn, ~p"/manufacturer")

    assert has_element?(view, "#stat-manufacturer-products", "1 GTIN registered")
    assert has_element?(view, "#stat-manufacturer-batches", "1 production batch")
    assert has_element?(view, "#serial-job-#{batch.id}", batch.batch_no)
    assert has_element?(view, "#serial-job-#{batch.id}", product.gtin)
    assert has_element?(view, "#serial-job-#{batch.id}", "No serials yet")
    assert has_element?(view, ".td-card-header", "Recent batches")
  end
end
