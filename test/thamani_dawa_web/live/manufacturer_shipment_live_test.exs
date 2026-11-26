defmodule ThamaniDawaWeb.ManufacturerShipmentLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.DistributorFixtures
  import ThamaniDawa.ManufacturerFixtures

  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Epcis.Outbox
  alias ThamaniDawa.Epcis.Urn
  alias ThamaniDawa.GS1.MemberApiStub
  alias ThamaniDawa.Manufacturing

  test "the shipments list filters by the shared status and date chips", %{conn: conn} do
    organization = manufacturer_organization_fixture()
    origin = manufacturing_site_fixture(organization.id)
    user = manufacturer_user_fixture(%{organization_id: organization.id, site_id: origin.id})

    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/manufacturer/shipments")

    assert has_element?(view, "#manufacturer-shipments-chip-status")
    assert has_element?(view, "#manufacturer-shipments-date-chip")
    refute has_element?(view, "#filter-dates")
    assert has_element?(view, "#manufacturer-shipments-date-chip .td-chip-value", "Any time")
    refute has_element?(view, ".td-data thead th", "Packed by")
    assert has_element?(view, ".td-data thead th", "Last updated")

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

  test "refresh reloads shipments created after the page was loaded", %{conn: conn} do
    organization = manufacturer_organization_fixture()
    origin = manufacturing_site_fixture(organization.id)
    user = manufacturer_user_fixture(%{organization_id: organization.id, site_id: origin.id})
    warehouse = warehouse_fixture(organization.id)
    destination = destination_fixture(organization.id)
    order_number = "PO-REFRESH-#{System.unique_integer([:positive])}"

    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/manufacturer/shipments")

    {:ok, shipment} =
      Distributor.create_shipment(
        organization.id,
        user,
        %{
          "order_number" => order_number,
          "origin_gln" => warehouse.gln,
          "destination_gln" => destination.gln
        },
        "manufacturer"
      )

    refute has_element?(view, "#shipment-d-#{shipment.id}-order")

    html = view |> element("#refresh-manufacturer-shipments") |> render_click()

    assert has_element?(view, "#shipment-d-#{shipment.id}-order", order_number)
    assert html =~ "Shipments refreshed."
  end

  test "creates and dispatches a manufacturer shipment with a manufacturer EPCIS event", %{
    conn: conn
  } do
    organization = manufacturer_organization_fixture()
    origin = manufacturing_site_fixture(organization.id)
    user = manufacturer_user_fixture(%{organization_id: organization.id, site_id: origin.id})
    destination = manufacturing_site_fixture(organization.id)

    conn = log_in_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/manufacturer/shipments")

    assert has_element?(
             view,
             "#create-manufacturer-shipment-from-ssccs[href='/manufacturer/shipments/create']"
           )

    assert has_element?(view, "#create-manufacturer-shipment-from-ssccs", "New shipment")
    refute has_element?(view, "#new-manufacturer-shipment")

    {:ok, view, _html} = live(conn, ~p"/manufacturer/shipments/new")
    assert has_element?(view, "#manufacturer-shipment-form")
    refute has_element?(view, "#manufacturer-shipment-ssccs")

    # Use the "one of your sites" destination so the GLN is a real select
    # field rather than the hidden input owned by the GLN picker.
    view |> element("#manufacturer-shipment-transfer") |> render_click()

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

  test "creates a shipment from packed SSCCs and sends EPCIS shipping on dispatch", %{
    conn: conn
  } do
    organization = manufacturer_organization_fixture()
    origin = manufacturing_site_fixture(organization.id)
    destination = manufacturing_site_fixture(manufacturer_organization_fixture().id)
    user = manufacturer_user_fixture(%{organization_id: organization.id, site_id: origin.id})

    MemberApiStub.add_glns([
      %{
        "gln" => destination.gln,
        "description" => "Test Licensee",
        "address" => destination.address || "Nairobi, Kenya",
        "location" => "Nairobi",
        "status" => "active",
        "company" => destination.name
      }
    ])

    shipper = pallet_ready_shipper_fixture(organization.id, order_number: "PO-88")
    {:ok, pallet} = Manufacturing.create_pallet_from_shippers(organization.id, [shipper.id])

    {:ok, loose} =
      Manufacturing.create_manual_sscc(organization.id, nil, %{
        "code" => "006141411234567890",
        "gtin" => "06141410000022",
        "from_gln" => origin.gln,
        "from_company_name" => "Factory",
        "from_address" => "12 Industrial Road, Nairobi",
        "to_gln" => destination.gln,
        "to_company_name" => "Warehouse",
        "to_address" => "8 Port Road, Mombasa",
        "status" => "completed",
        "count_of_trade_items" => 2
      })

    product = manufacturer_product_fixture(organization.id)

    batch =
      manufacturer_batch_fixture(organization.id, product.id, %{batch_no: "LOT-A"})

    {:ok, _linked} = Manufacturing.add_batch_to_sscc(organization.id, shipper.id, batch.id)

    for index <- 1..4 do
      {:ok, _serial} =
        Manufacturing.create_manual_serial(organization.id, batch, shipper, %{
          "serial" => "SN-#{index}"
        })
    end

    conn = log_in_user(conn, user)

    {:ok, list, _html} = live(conn, ~p"/manufacturer/shipments")

    assert has_element?(
             list,
             "#create-manufacturer-shipment-from-ssccs[href='/manufacturer/shipments/create']"
           )

    {:ok, view, _html} = live(conn, ~p"/manufacturer/shipments/create")
    assert has_element?(view, "#create-manufacturer-shipment")
    assert has_element?(view, "#manufacturer-shipment-ssccs")
    assert has_element?(view, "#destination-gln-search-input")
    refute has_element?(view, "#manufacturer-shipments")

    assert has_element?(view, "#manufacturer-shipment-ssccs", "LOT-A")
    assert has_element?(view, "#manufacturer-shipment-ssccs", "SSCC #{shipper.code}")
    assert has_element?(view, "#manufacturer-shipment-ssccs", "PO-88")
    assert has_element?(view, "#manufacturer-shipment-ssccs", "Warehouse")
    assert has_element?(view, "#manufacturer-shipment-ssccs", "Standalone")

    view
    |> element("#destination-gln-search-input")
    |> render_keyup(%{"value" => destination.gln})

    render_async(view)

    assert has_element?(view, "#destination-gln-search-option-#{destination.gln}")

    view
    |> element("#destination-gln-search-option-#{destination.gln}")
    |> render_click()

    view
    |> form("#manufacturer-shipment-form", %{
      "shipment" => %{
        "order_number" => "PO-88",
        "sscc_ids" => [to_string(shipper.id), to_string(loose.id)]
      }
    })
    |> render_submit()

    [shipment] = Manufacturing.list_shipments(organization.id)
    assert shipment.status == "draft"

    assert Enum.sort(Enum.map(shipment.shipper_ssccs, & &1.id)) ==
             Enum.sort([shipper.id, loose.id])

    assert_redirect(view, ~p"/manufacturer/shipments/packed/#{shipment.id}")
    refute Enum.any?(Outbox.list_events(organization.id), &(&1.event_type == "shipping"))

    {:ok, show, _html} = live(conn, ~p"/manufacturer/shipments/packed/#{shipment.id}")

    assert has_element?(show, ".td-page-header", shipment.reference)
    assert has_element?(show, ".td-page-header", "Last updated")
    refute has_element?(show, "#packed-shipment-summary")
    assert has_element?(show, "#packed-shipment-origin", shipment.origin_company)
    assert has_element?(show, "#packed-shipment-origin", shipment.origin_address || "—")
    assert has_element?(show, "#packed-shipment-destination", shipment.destination_company)
    assert has_element?(show, "#packed-shipment-destination", shipment.destination_address || "—")
    assert has_element?(show, "#packed-shipment-lifecycle", "Units packed and verified")
    assert has_element?(show, "#packed-shipment-packing")
    assert has_element?(show, "#shipment-pallets-table")
    assert has_element?(show, "#shipment-pallets-table thead th", "Pallet")
    assert has_element?(show, "#shipment-pallet-#{pallet.id}", pallet.code)
    assert has_element?(show, "#shipment-pallet-#{pallet.id}", shipper.code)
    assert has_element?(show, "#shipment-pallet-#{pallet.id}", "View")

    assert has_element?(show, "#shipment-shippers-table")
    assert has_element?(show, "#shipment-sscc-#{shipper.id}", shipper.code)

    assert has_element?(
             show,
             "#shipment-sscc-id-#{shipper.id}-peek .printable-sscc-label",
             "From Address"
           )

    assert has_element?(show, "#shipment-sscc-#{shipper.id}", pallet.code)
    assert has_element?(show, "#shipment-sscc-#{shipper.id}", "LOT-A")

    assert has_element?(
             show,
             "#shipment-sscc-#{shipper.id}",
             Date.to_iso8601(shipper.production_date)
           )

    assert has_element?(show, "#expand-sscc-#{shipper.id}", "4 serials")
    assert has_element?(show, "#shipment-sscc-#{loose.id}", loose.code)
    assert has_element?(show, "#shipment-sscc-#{loose.id}", "Standalone")
    assert has_element?(show, "#expand-sscc-#{loose.id}", "0 serials")

    show |> element("#expand-sscc-#{shipper.id}") |> render_click()

    assert has_element?(show, "#shipper-serials-#{shipper.id}", "4 serials")
    assert has_element?(show, "#shipper-serials-#{shipper.id}", "SN-1")

    show |> element("#expand-sscc-#{loose.id}") |> render_click()

    assert has_element?(show, "#shipper-serials-#{loose.id}", "No serials recorded")
    refute has_element?(show, "#packed-items-table")
    refute has_element?(show, "#packed-shipment-table")
    refute has_element?(show, "#packed-shipment-epcis")

    show |> element("#dispatch-shipment") |> render_click()
    show |> element("#confirm-dispatch") |> render_click()

    assert Manufacturing.get_shipment!(organization.id, shipment.id).status == "approved"

    event = Enum.find(Outbox.list_events(organization.id), &(&1.event_type == "shipping"))
    assert event.source_type == "manufacturer_shipment"
    assert event.source_id == shipment.id
    assert {:ok, pallet_epc} = Urn.sscc(pallet.code, 7)
    assert {:ok, loose_epc} = Urn.sscc(loose.code, 7)
    assert Enum.sort(event.payload["epcList"]) == Enum.sort([pallet_epc, loose_epc])

    assert has_element?(show, "#packed-shipment-lifecycle", user.name)
    refute has_element?(show, "#packed-shipment-epcis")
  end
end
