defmodule ThamaniDawaWeb.ManufacturerPalletNewLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.ManufacturerFixtures

  alias ThamaniDawa.Gln
  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Manufacturing.Shipment
  alias ThamaniDawa.Manufacturing.ShipmentItem
  alias ThamaniDawa.Repo

  @destination "6164003000024"

  setup %{conn: conn} do
    organization = manufacturer_organization_fixture()
    site = manufacturing_site_fixture(organization.id)
    user = manufacturer_user_fixture(%{organization_id: organization.id, site_id: site.id})
    %{conn: log_in_user(conn, user), organization: organization}
  end

  defp shipper!(organization_id, code, opts \\ []) do
    {:ok, sscc} =
      Manufacturing.create_manual_sscc(organization_id, nil, %{
        "code" => code,
        "gtin" => Keyword.get(opts, :gtin, "06141410000011"),
        "batch" => Keyword.get(opts, :batch, "LOT-A"),
        "count_of_trade_items" => Keyword.get(opts, :count, 5),
        "from_gln" => Gln.generate!(),
        "from_company_name" => "Factory",
        "to_gln" => Keyword.get(opts, :to_gln, @destination),
        "to_company_name" => Keyword.get(opts, :to_company, "Warehouse")
      })

    sscc
  end

  defp scan(view, code) do
    view |> form("#pallet-scan-form", %{code: code}) |> render_submit()
  end

  test "scans shippers that share a destination and creates a local pallet", %{
    conn: conn,
    organization: organization
  } do
    a = shipper!(organization.id, "SHIP-A", batch: "LOT-A")
    b = shipper!(organization.id, "SHIP-B", batch: "LOT-B", gtin: "06141410000028")
    _other = shipper!(organization.id, "SHIP-C")

    {:ok, view, _html} = live(conn, ~p"/manufacturer/aggregations/pallets/new")

    assert has_element?(view, "#pallet-back", "Back to Aggregation")
    refute has_element?(view, "#open-create-pallet:not([disabled])")

    scan(view, a.code)
    scan(view, b.code)
    assert has_element?(view, "#pallet-scanned-#{a.id}")
    assert has_element?(view, "#pallet-scanned-#{b.id}")

    view |> element("#open-create-pallet") |> render_click()
    assert has_element?(view, "#create-pallet-modal")
    view |> element("#create-pallet-sscc") |> render_click()

    [pallet] = Manufacturing.list_pallets(organization.id)
    assert String.starts_with?(pallet.code, "PAL-")
    assert_redirect(view, ~p"/manufacturer/aggregations/pallets/#{pallet.id}")
    assert pallet.shipper_ssccs |> Enum.map(& &1.id) |> Enum.sort() == Enum.sort([a.id, b.id])

    {:ok, show, _html} = live(conn, ~p"/manufacturer/aggregations/pallets/#{pallet.id}")
    assert has_element?(show, "#pallet-shipper-#{a.id}")
    assert has_element?(show, "#ship-pallet", "Ship this pallet")
    assert has_element?(show, "#print-pallet-label", "Print label")
  end

  test "rejects a duplicate, an empty shipper, a different destination, and one already shipped",
       %{conn: conn, organization: organization} do
    kept = shipper!(organization.id, "SHIP-KEEP")
    duplicate = shipper!(organization.id, "SHIP-DUP")
    empty = shipper!(organization.id, "SHIP-EMPTY", count: 0)
    other_dest = shipper!(organization.id, "SHIP-OTHER", to_gln: Gln.generate!())
    shipped = shipper!(organization.id, "SHIP-GONE")

    shipment =
      Repo.insert!(%Shipment{
        organization_id: organization.id,
        reference: "SHP-#{System.unique_integer([:positive])}",
        order_number: "PO-24109",
        origin_gln: shipped.from_gln,
        origin_company: "Factory",
        origin_address: "Nairobi",
        destination_gln: shipped.to_gln,
        destination_company: "Warehouse",
        destination_address: "Mombasa"
      })

    Repo.insert!(%ShipmentItem{
      manufacturer_shipment_id: shipment.id,
      manufacturer_shipper_sscc_id: shipped.id
    })

    {:ok, view, _html} = live(conn, ~p"/manufacturer/aggregations/pallets/new")
    scan(view, kept.code)
    scan(view, duplicate.code)
    scan(view, duplicate.code)
    assert has_element?(view, "#pallet-rejection-SHIPDUP", "Already on this pallet")

    view |> element("#pallet-rejection-SHIPDUP button") |> render_click()
    refute has_element?(view, "#pallet-rejection-SHIPDUP")

    scan(view, empty.code)
    assert has_element?(view, "#pallet-rejection-SHIPEMPTY", "Empty shipper")

    scan(view, other_dest.code)
    assert has_element?(view, "#pallet-rejection-SHIPOTHER", "Different destination")

    scan(view, shipped.code)
    assert has_element?(view, "#pallet-rejection-SHIPGONE", "Already on shipment PO-24109")

    scan(view, "NOT-A-SHIPPER")
    assert has_element?(view, "#pallet-rejection-NOTASHIPPER", "No shipper with that SSCC")
    refute has_element?(view, "#pallet-scanned-#{empty.id}")
    refute has_element?(view, "#pallet-scanned-#{shipped.id}")
  end

  test "opening from a shipper preselects it and names the back link", %{
    conn: conn,
    organization: organization
  } do
    shipper = shipper!(organization.id, "SHIP-FROM")

    {:ok, view, _html} =
      live(conn, ~p"/manufacturer/aggregations/pallets/new?#{[sscc: shipper.id, return_to: ~p"/manufacturer/sscc/#{shipper.id}/serials"]}")

    assert has_element?(view, "#pallet-back", "Back to shipper SHIP-FROM")
    assert has_element?(view, "#pallet-scanned-#{shipper.id}")
  end
end
