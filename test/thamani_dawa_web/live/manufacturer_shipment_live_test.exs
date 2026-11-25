defmodule ThamaniDawaWeb.ManufacturerShipmentLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.DistributorFixtures
  import ThamaniDawa.ManufacturerFixtures

  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Epcis.Outbox

  test "the shipments list filters by the shared status and date chips", %{conn: conn} do
    organization = manufacturer_organization_fixture()
    origin = manufacturing_site_fixture(organization.id)
    user = manufacturer_user_fixture(%{organization_id: organization.id, site_id: origin.id})

    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/manufacturer/shipments")

    assert has_element?(view, "#manufacturer-shipments-chip-status")
    assert has_element?(view, "#manufacturer-shipments-date-chip")
    refute has_element?(view, "#filter-dates")
    assert has_element?(view, "#manufacturer-shipments-date-chip .td-chip-value", "Any time")

    view |> element("#manufacturer-shipments-date-preset-7d") |> render_click()
    assert_patch(view, ~p"/manufacturer/shipments?date=7d")
    assert has_element?(view, "#manufacturer-shipments-date-chip .td-chip-value", "Last 7 days")

    view
    |> form("#manufacturer-shipments-date-form", %{
      "date_from" => "2026-11-01",
      "date_to" => "2026-11-20"
    })
    |> render_submit()

    assert_patch(
      view,
      ~p"/manufacturer/shipments?date=custom&date_from=2026-11-01&date_to=2026-11-20"
    )

    view |> element("#manufacturer-shipments-status-draft") |> render_click()

    assert_patch(
      view,
      ~p"/manufacturer/shipments?date=custom&date_from=2026-11-01&date_to=2026-11-20&status=draft"
    )
  end

  test "creates and dispatches a manufacturer shipment with a manufacturer EPCIS event", %{
    conn: conn
  } do
    organization = manufacturer_organization_fixture()
    origin = manufacturing_site_fixture(organization.id)
    user = manufacturer_user_fixture(%{organization_id: organization.id, site_id: origin.id})
    destination_org = manufacturer_organization_fixture()
    destination = manufacturing_site_fixture(destination_org.id)

    conn = log_in_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/manufacturer/shipments")

    assert has_element?(view, "#new-manufacturer-shipment")

    {:ok, view, _html} = live(conn, ~p"/manufacturer/shipments/new")
    assert has_element?(view, "#manufacturer-shipment-form")
    refute has_element?(view, "#manufacturer-shipment-ssccs")

    view
    |> form("#manufacturer-shipment-form", %{
      "shipment" => %{
        "order_number" => "MO-1001",
        "origin_gln" => origin.gln,
        "destination_gln" => destination.gln
      }
    })
    |> render_submit()

    [shipment] =
      Distributor.list_shipments(organization.id, %{participant_tier: "manufacturer"}).entries

    assert shipment.status == "draft"
    assert shipment.shippers == []
    assert shipment.participant_tier == "manufacturer"
    assert_redirect(view, ~p"/manufacturer/shipments/#{shipment.id}")

    mobile_user = mobile_user_fixture(organization.id, %{"site_id" => origin.id})
    batch = received_unit_fixture(organization.id, origin.id, user.id)
    prepay_allowance_fixture(organization.id, user)
    {:ok, _shipment} = Distributor.select_shipment(mobile_user, shipment.id)
    {:ok, shipper} = Distributor.create_shipper(mobile_user, shipment.id, %{})

    {:ok, _item} =
      Distributor.scan_item(mobile_user, shipper.id, %{
        "raw_data_matrix" => data_matrix_for(batch)
      })

    {:ok, _shipment} = Distributor.submit_shipment(mobile_user, shipment.id)

    {:ok, show, _html} = live(conn, ~p"/manufacturer/shipments/#{shipment.id}")
    assert has_element?(show, "#approve-manufacturer-shipment")
    show |> element("#approve-manufacturer-shipment") |> render_click()

    shipment = Distributor.get_shipment!(organization.id, shipment.id)
    assert shipment.status == "approved"
    refute has_element?(show, "#approve-manufacturer-shipment")

    event = Enum.find(Outbox.list_events(organization.id), &(&1.event_type == "shipping"))
    assert event.participant_tier == "manufacturer"
    assert event.source_type == "shipment"
    assert event.source_id == shipment.id
    assert event.payload["bizStep"] == "shipping"
    assert length(event.payload["epcList"]) == 1
    assert [%{"bizTransaction" => transaction}] = event.payload["bizTransactionList"]
    assert transaction =~ "MO-1001"
  end
end
