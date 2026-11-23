defmodule ThamaniDawaWeb.ManufacturerPalletNewLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.ManufacturerFixtures

  alias ThamaniDawa.Gln
  alias ThamaniDawa.Manufacturing

  setup %{conn: conn} do
    organization = manufacturer_organization_fixture()
    site = manufacturing_site_fixture(organization.id)
    user = manufacturer_user_fixture(%{organization_id: organization.id, site_id: site.id})
    %{conn: log_in_user(conn, user), organization: organization}
  end

  defp shipper!(organization_id, code, gtin, batch) do
    {:ok, sscc} =
      Manufacturing.create_manual_sscc(organization_id, nil, %{
        "code" => code,
        "gtin" => gtin,
        "batch" => batch,
        "count_of_trade_items" => 5,
        "from_gln" => Gln.generate!(),
        "from_company_name" => "Factory",
        "to_gln" => Gln.generate!(),
        "to_company_name" => "Warehouse"
      })

    sscc
  end

  test "searches, selects shippers across batches and creates a pallet", %{
    conn: conn,
    organization: organization
  } do
    a = shipper!(organization.id, "SHIP-A", "06141410000011", "LOT-A")
    b = shipper!(organization.id, "SHIP-B", "06141410000028", "LOT-B")
    c = shipper!(organization.id, "SHIP-C", "06141410000035", "LOT-C")

    {:ok, view, _html} = live(conn, ~p"/manufacturer/aggregations/pallets/new")

    view |> form("#pallet-shipper-search", %{"q" => "lot-b"}) |> render_change()
    assert has_element?(view, "#pallet-option-#{b.id}")
    refute has_element?(view, "#pallet-option-#{a.id}")
    view |> element("#pallet-option-#{b.id}") |> render_click()

    view |> form("#pallet-shipper-search", %{"q" => ""}) |> render_change()
    view |> element("#pallet-option-#{a.id}") |> render_click()

    view |> element("#create-pallet-sscc") |> render_click()

    [pallet] = Manufacturing.list_pallets(organization.id)
    assert_redirect(view, ~p"/manufacturer/aggregations/pallets/#{pallet.id}")
    assert pallet.shipper_ssccs |> Enum.map(& &1.id) |> Enum.sort() == Enum.sort([a.id, b.id])

    {:ok, show, _html} = live(conn, ~p"/manufacturer/aggregations/pallets/#{pallet.id}")
    assert has_element?(show, "#pallet-shipper-#{a.id}")
    assert has_element?(show, "#pallet-shipper-#{b.id}")
    refute has_element?(show, "#pallet-shipper-#{c.id}")
  end
end
