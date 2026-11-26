defmodule ThamaniDawaWeb.ManufacturerPalletNewLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.ManufacturerFixtures

  alias ThamaniDawa.Epcis.Outbox
  alias ThamaniDawa.Gln
  alias ThamaniDawa.GS1.MemberApiStub
  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Manufacturing.Shipment
  alias ThamaniDawa.Manufacturing.ShipmentItem
  alias ThamaniDawa.Repo

  setup %{conn: conn} do
    MemberApiStub.reset()

    organization = manufacturer_organization_fixture()
    site = manufacturing_site_fixture(organization.id)
    user = manufacturer_user_fixture(%{organization_id: organization.id, site_id: site.id})
    %{conn: log_in_user(conn, user), organization: organization}
  end

  defp shipper!(organization_id, _code, opts \\ []) do
    pallet_ready_shipper_fixture(
      organization_id,
      Keyword.take(opts, [:batch, :count, :to_gln])
    )
  end

  defp dom_id(code), do: String.replace(code, ~r/[^A-Za-z0-9]/, "")

  defp scan(view, code) do
    view |> form("#pallet-scan-form", %{code: code}) |> render_submit()
  end

  test "scans shippers, mints a pallet SSCC, and records aggregation", %{
    conn: conn,
    organization: organization
  } do
    a = shipper!(organization.id, "SHIP-A", batch: "LOT-A")
    b = shipper!(organization.id, "SHIP-B", batch: "LOT-B")
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
    assert has_element?(view, ~s(input#pallet-order-number[value="PO-24109"]))

    view
    |> form("#pallet-details-form", %{
      "pallet" => %{"order_number" => "PO-PALLET-1", "to_address" => "12 Port Road, Mombasa"}
    })
    |> render_submit()

    [pallet] = Manufacturing.list_pallets(organization.id)
    assert String.match?(pallet.code, ~r/^\d{18}$/)
    refute String.starts_with?(pallet.code, "PAL-")

    assert pallet.to_address == "12 Port Road, Mombasa"
    assert_redirect(view, ~p"/manufacturer/aggregations/pallets/#{pallet.id}")
    assert pallet.shipper_ssccs |> Enum.map(& &1.id) |> Enum.sort() == Enum.sort([a.id, b.id])

    [event] =
      Enum.filter(Outbox.list_events(organization.id), &(&1.event_type == "pallet_packing"))

    assert event.source_type == "manufacturer_pallet"
    assert event.source_id == pallet.id
    assert event.payload["type"] == "AggregationEvent"
    assert event.payload["action"] == "ADD"
    assert length(event.payload["childEPCs"]) == 2

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
    duplicate_id = "pallet-rejection-#{dom_id(duplicate.code)}"
    assert has_element?(view, "##{duplicate_id}", "Already on this pallet")

    view |> element("##{duplicate_id} button") |> render_click()
    refute has_element?(view, "##{duplicate_id}")

    scan(view, empty.code)
    assert has_element?(view, "#pallet-rejection-#{dom_id(empty.code)}", "Empty shipper")

    scan(view, other_dest.code)

    assert has_element?(
             view,
             "#pallet-rejection-#{dom_id(other_dest.code)}",
             "Different destination"
           )

    scan(view, shipped.code)

    assert has_element?(
             view,
             "#pallet-rejection-#{dom_id(shipped.code)}",
             "Already on shipment PO-24109"
           )

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
      live(
        conn,
        ~p"/manufacturer/aggregations/pallets/new?#{[sscc: shipper.id, return_to: ~p"/manufacturer/sscc/#{shipper.id}/serials"]}"
      )

    assert has_element?(view, "#pallet-back", "Back to shipper #{shipper.code}")
    assert has_element?(view, "#pallet-scanned-#{shipper.id}")
  end
end
