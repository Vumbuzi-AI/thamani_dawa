defmodule ThamaniDawaWeb.ManufacturerAggregationDashboardTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.ManufacturerFixtures

  alias ThamaniDawa.Gln
  alias ThamaniDawa.Manufacturing

  setup %{conn: conn} do
    organization = manufacturer_organization_fixture()
    site = manufacturing_site_fixture(organization.id)
    user = manufacturer_user_fixture(%{organization_id: organization.id, site_id: site.id})
    %{conn: log_in_user(conn, user), organization: organization, site: site}
  end

  test "lists pallet and standalone shipper SSCCs", %{conn: conn, organization: organization} do
    {:ok, view, _html} = live(conn, ~p"/manufacturer/aggregations")

    assert has_element?(view, "#add-sscc", "Add SSCC")
    assert has_element?(view, "#create-pallet", "Group shippers")
    assert has_element?(view, "#aggregation-pallets-empty")
    assert has_element?(view, "#aggregation-shippers-empty")

    {:ok, pallet} =
      Manufacturing.create_pallet(organization.id, %{
        "code" => "361640010000000184",
        "from_company_name" => "Thamani Pharma Limited",
        "to_company_name" => "Kilimo Distributors Ltd"
      })

    {:ok, _shipper} =
      Manufacturing.create_manual_sscc(organization.id, nil, %{
        "code" => "361640010000000252",
        "from_gln" => Gln.generate!(),
        "from_company_name" => "Thamani Pharma Limited",
        "to_gln" => Gln.generate!(),
        "to_company_name" => "Afya Bora Health Ltd",
        "count_of_trade_items" => 120
      })

    {:ok, view, _html} = live(conn, ~p"/manufacturer/aggregations")

    refute has_element?(view, "#aggregation-pallets-empty")
    refute has_element?(view, "#aggregation-shippers-empty")
    assert has_element?(view, "#aggregation-pallet-#{pallet.id}", "361640010000000184")
    assert has_element?(view, "#aggregation-shippers", "361640010000000252")
    assert has_element?(view, "#aggregation-shippers", "120")
  end
end
