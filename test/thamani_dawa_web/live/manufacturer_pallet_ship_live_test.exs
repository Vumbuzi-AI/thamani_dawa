defmodule ThamaniDawaWeb.ManufacturerPalletShipLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.ManufacturerFixtures

  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Gln
  alias ThamaniDawa.Manufacturing

  @destination "6164003000024"

  setup %{conn: conn} do
    organization = manufacturer_organization_fixture()
    site = manufacturing_site_fixture(organization.id)
    user = manufacturer_user_fixture(%{organization_id: organization.id, site_id: site.id})
    %{conn: log_in_user(conn, user), organization: organization, user: user}
  end

  defp shipper!(organization_id, code) do
    {:ok, sscc} =
      Manufacturing.create_manual_sscc(organization_id, nil, %{
        "code" => code,
        "gtin" => "06141410000011",
        "batch" => "LOT-A",
        "count_of_trade_items" => 4,
        "from_gln" => Gln.generate!(),
        "from_company_name" => "Factory",
        "from_address" => "Nairobi",
        "to_gln" => @destination,
        "to_company_name" => "Warehouse",
        "to_address" => "Mombasa"
      })

    sscc
  end

  test "ships a pallet as one shipment and dispatches it", %{
    conn: conn,
    organization: organization
  } do
    a = shipper!(organization.id, "SHIP-A")
    b = shipper!(organization.id, "SHIP-B")
    {:ok, pallet} = Manufacturing.create_pallet_from_shippers(organization.id, [a.id, b.id])

    {:ok, form, _html} =
      live(conn, ~p"/manufacturer/shipments/new?#{[pallet_id: pallet.id]}")

    assert has_element?(form, "#pallet-shipment-back", "Back to pallet #{pallet.code}")
    assert has_element?(form, "#pallet-shipment-shipper-#{a.id}")
    refute has_element?(form, "#manufacturer-shipment-form")

    form
    |> form("#pallet-shipment-form", %{order_number: "PO-24109"})
    |> render_submit()

    [shipment] = Manufacturing.list_shipments(organization.id)
    assert shipment.status == "draft"
    assert shipment.order_number == "PO-24109"
    assert shipment.origin_company == "Factory"
    assert Enum.map(shipment.shipper_ssccs, & &1.id) |> Enum.sort() == Enum.sort([a.id, b.id])

    assert Distributor.list_shipments(organization.id, %{participant_tier: "manufacturer"}).entries ==
             []

    assert_redirect(form, ~p"/manufacturer/shipments/packed/#{shipment.id}")

    {:ok, show, _html} = live(conn, ~p"/manufacturer/shipments/packed/#{shipment.id}")
    assert has_element?(show, "#shipment-sscc-#{a.id}")
    show |> element("#dispatch-shipment") |> render_click()
    assert has_element?(show, "#dispatch-shipment-modal")
    show |> element("#confirm-dispatch") |> render_click()

    shipment = Manufacturing.get_shipment!(organization.id, shipment.id)
    assert shipment.status == "approved"
    refute has_element?(show, "#dispatch-shipment")

    {:ok, list, _html} = live(conn, ~p"/manufacturer/shipments")
    assert has_element?(list, "#review-m-#{shipment.id}")
  end
end
