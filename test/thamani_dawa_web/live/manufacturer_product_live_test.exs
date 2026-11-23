defmodule ThamaniDawaWeb.ManufacturerProductLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.ManufacturerFixtures

  alias ThamaniDawa.Manufacturing

  defp manufacturer_session(_conn) do
    organization = manufacturer_organization_fixture()
    site = manufacturing_site_fixture(organization.id)
    user = manufacturer_user_fixture(%{organization_id: organization.id, site_id: site.id})
    product = manufacturer_product_fixture(organization.id)

    %{organization: organization, site: site, user: user, product: product}
  end

  test "a non-manufacturer user is redirected away from the manufacturer portal", %{conn: conn} do
    user = staff_fixture(%{role: :pharmacist})
    conn = log_in_user(conn, user)

    assert {:error, {redirect, %{to: _to}}} = live(conn, ~p"/manufacturer")
    assert redirect in [:redirect, :live_redirect]
  end

  test "lists products with their serial and SSCC counts", %{conn: conn} do
    %{user: user, product: product} = manufacturer_session(conn)
    conn = log_in_user(conn, user)

    {:ok, lv, html} = live(conn, ~p"/manufacturer/products")

    assert html =~ "Products"
    assert has_element?(lv, "#manufacturer-products", product.gtin)
    assert has_element?(lv, "#manufacturer-products", product.name)
    assert has_element?(lv, "#product-#{product.id}-serials")
    assert has_element?(lv, "#product-#{product.id}-ssccs")
    assert has_element?(lv, "#product-#{product.id}-add-serial")
    assert has_element?(lv, "#manufacturer-number-generated")
    assert has_element?(lv, "#manufacturer-maximum")
    refute has_element?(lv, "#amount-to-pay")
  end

  test "uses GS1 product counts for matching GTINs", %{conn: conn} do
    %{user: user, product: product} = manufacturer_session(conn)

    ThamaniDawa.GS1.MemberApiStub.put_products([
      %{
        "gtin" => product.gtin,
        "name" => product.name,
        "description" => product.description,
        "serial_count" => 17,
        "sscc_count" => 3
      }
    ])

    conn = log_in_user(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/manufacturer/products")

    assert has_element?(lv, "#product-#{product.id}-serial-count", "17")
    assert has_element?(lv, "#product-#{product.id}-sscc-count", "3")
    assert has_element?(lv, "#manufacturer-number-generated", "20")
  end

  test "adds a product via the modal form", %{conn: conn} do
    %{organization: organization, user: user} = manufacturer_session(conn)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/manufacturer/products/new")

    lv
    |> form("#manufacturer-product-form", %{
      "product" => %{
        "gtin" => "06160000000012",
        "name" => "Amoxicillin 250mg",
        "description" => "Antibiotic capsules"
      }
    })
    |> render_submit()

    added =
      Enum.find(Manufacturing.list_products(organization.id), &(&1.name == "Amoxicillin 250mg"))

    assert added.name == "Amoxicillin 250mg"
  end

  test "make-to-stock path creates a batch and primary serials without an SSCC", %{
    conn: conn
  } do
    %{organization: organization, site: site, user: user, product: product} =
      manufacturer_session(conn)

    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/manufacturer/products/#{product.gtin}/serials/new")

    assert has_element?(lv, "#serial-wizard-product", product.gtin)
    refute has_element?(lv, "#manufacturer-serial-generation-form")

    lv |> element("#serial-wizard-mode-stock") |> render_click()

    assert has_element?(lv, "#manufacturer-serial-generation-form")
    # Step 2 dates are the TD date picker, never the browser's native calendar.
    assert has_element?(lv, ~s(.td-dp [data-dp-input][name="serial_generation[production_date]"]))
    assert has_element?(lv, ~s(.td-dp [data-dp-input][name="serial_generation[expiry_date]"]))
    refute has_element?(lv, ~s(input[type="date"]))
    refute has_element?(lv, ~s([name="serial_generation[shipper_quantity]"]))
    refute has_element?(lv, ~s([name="serial_generation[from_gln]"]))

    lv
    |> form("#manufacturer-serial-generation-form", %{
      "serial_generation" => %{
        "batch_no" => "LOT-2026-11",
        "production_date" => "2026-11-20",
        "expiry_date" => "2027-11-20",
        "primary_quantity" => "5"
      }
    })
    |> render_submit()

    [{batch, 5}] = Manufacturing.list_batches(organization.id, product.id)
    assert [serial | _] = Manufacturing.list_serials(organization.id, batch.id)
    assert serial.serial != nil
    assert Manufacturing.list_sscc_groups(organization.id, product.id) == []
    assert batch.production_date == ~D[2026-11-20]
    assert batch.expiry_date == ~D[2027-11-20]

    request =
      Enum.find(ThamaniDawa.GS1.MemberApiStub.serial_requests(), &(&1["barcode"] == product.gtin))

    assert request["create_shippers"] == false
    refute Map.has_key?(request, "shipper_qty")
    refute Map.has_key?(request, "from")
    refute Map.has_key?(request, "to")

    events = ThamaniDawa.Epcis.Outbox.list_events(organization.id)

    event =
      Enum.find(
        events,
        &(&1.participant_tier == "manufacturer" and &1.event_type == "commissioning")
      )

    assert event

    assert event.payload["bizStep"] == "commissioning"

    assert get_in(event.payload, ["readPoint", "id"]) =~ String.slice(site.gln, 0, 6)
  end

  test "make-to-order path generates primary serials then mints shipper SSCCs", %{
    conn: conn
  } do
    %{organization: organization, site: site, user: user, product: product} =
      manufacturer_session(conn)

    other_facility =
      manufacturing_site_fixture(organization.id, %{
        name: "Secondary Plant",
        address: "2 Manufacturing Way"
      })

    ThamaniDawa.GS1.MemberApiStub.put_glns([
      %{
        "gln" => site.gln,
        "description" => site.name,
        "address" => site.address,
        "location" => "Nairobi",
        "company" => site.name
      }
    ])

    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/manufacturer/products/#{product.gtin}/serials/new")

    lv |> element("#serial-wizard-mode-order") |> render_click()

    assert has_element?(lv, ~s([name="serial_generation[shipper_quantity]"]))
    refute has_element?(lv, ~s([name="serial_generation[from_gln]"]))

    lv
    |> form("#manufacturer-serial-generation-form", %{
      "serial_generation" => %{
        "batch_no" => "LOT-2026-ORDER",
        "production_date" => "2026-11-20",
        "expiry_date" => "2027-11-20",
        "primary_quantity" => "4",
        "shipper_quantity" => "2"
      }
    })
    |> render_change()

    lv |> element("#serial-wizard-next") |> render_click()

    assert has_element?(lv, ~s([name="serial_generation[from_gln]"]))
    assert has_element?(lv, "#serial_generation_from_gln-cb")
    assert has_element?(lv, "#serial_generation_from_gln-cb[data-options*='Secondary Plant']")

    lv
    |> form("#manufacturer-serial-generation-form", %{
      "serial_generation" => %{"from_gln" => other_facility.gln}
    })
    |> render_change()

    assert has_element?(
             lv,
             ~s(input[name="serial_generation[from_company_name]"][value="Secondary Plant"])
           )

    assert has_element?(
             lv,
             ~s(input[name="serial_generation[from_address]"][value="2 Manufacturing Way"])
           )

    assert has_element?(lv, "#serial-generation-to-gln-combobox")
    refute has_element?(lv, "#serial-generation-to-gln-results")

    lv
    |> element("#serial_generation_to_gln_search")
    |> render_keyup(%{"value" => "c"})

    assert has_element?(lv, "#serial-generation-to-gln-search-hint")

    lv
    |> element("#serial_generation_to_gln_search")
    |> render_keyup(%{"value" => site.gln})

    render_async(lv)

    assert has_element?(lv, "#serial-generation-to-gln-results")
    assert has_element?(lv, "#serial-generation-to-gln-#{site.gln}", site.name)

    lv
    |> element("#serial-generation-to-gln-#{site.gln}")
    |> render_click()

    assert has_element?(
             lv,
             ~s(input[name="serial_generation[to_company_name]"][value="#{site.name}"][readonly])
           )

    assert has_element?(
             lv,
             ~s(input[name="serial_generation[to_address]"][value="#{site.address}"][readonly])
           )

    lv
    |> form("#manufacturer-serial-generation-form", %{
      "serial_generation" => %{
        "from_gln" => other_facility.gln,
        "to_gln" => site.gln,
        "to_company_name" => "Untrusted submitted name",
        "to_address" => "Untrusted submitted address"
      }
    })
    |> render_submit()

    [{batch, 4}] = Manufacturing.list_batches(organization.id, product.id)
    groups = Manufacturing.list_sscc_groups(organization.id, product.id)
    assert length(groups) == 2
    assert Enum.all?(groups, &(&1.serial_count == 2))

    [%{sscc: sscc} | _] = groups
    assert sscc.from_gln == other_facility.gln
    assert sscc.to_gln == site.gln
    assert sscc.to_company_name == site.name
    assert sscc.to_address == site.address
    assert sscc.manufacturer_pallet_id

    pack_events =
      organization.id
      |> ThamaniDawa.Epcis.Outbox.list_events()
      |> Enum.filter(&(&1.participant_tier == "manufacturer" and &1.event_type == "packing"))

    assert length(pack_events) == 2
    assert Enum.all?(pack_events, &(length(&1.payload["childEPCs"]) == 2))

    commission_event =
      organization.id
      |> ThamaniDawa.Epcis.Outbox.list_events()
      |> Enum.find(&(&1.participant_tier == "manufacturer" and &1.event_type == "commissioning"))

    assert commission_event
    assert length(commission_event.payload["epcList"]) == 4

    refute Enum.any?(
             ThamaniDawa.Epcis.Outbox.list_events(organization.id),
             &(&1.event_type == "shipping")
           )

    assert Enum.count(Manufacturing.list_serials(organization.id, batch.id)) == 4

    serial_request =
      Enum.find(ThamaniDawa.GS1.MemberApiStub.serial_requests(), &(&1["barcode"] == product.gtin))

    assert serial_request["shipper_qty"] == 5
    assert serial_request["from"] == %{"gln" => site.gln}
    assert serial_request["to"] == %{"gln" => site.gln}
  end

  test "serial and SSCC eye links open org-scoped drill-downs", %{conn: conn} do
    %{organization: organization, user: user, product: product} = manufacturer_session(conn)
    batch = manufacturer_batch_fixture(organization.id, product.id)

    assert {:ok, %{serials: [_ | _]}} =
             Manufacturing.generate_primary_serials(
               organization.id,
               product,
               %{
                 "batch_no" => batch.batch_no,
                 "production_date" => Date.to_iso8601(batch.production_date),
                 "expiry_date" => Date.to_iso8601(batch.expiry_date)
               },
               3,
               manufacturer_session_gln(user)
             )

    conn = log_in_user(conn, user)

    {:ok, serials, _html} = live(conn, ~p"/manufacturer/products/#{product.gtin}/serials")
    # Batches and serials come from the GS1 member API (stubbed here).
    assert has_element?(serials, "#serial-batch-#{batch.batch_no}", "3")
    assert has_element?(serials, "#primary-serial-batch-details")
    assert has_element?(serials, "#primary-serial-gtin", product.gtin)
    assert has_element?(serials, "#primary-serial-batch-number", batch.batch_no)
    assert has_element?(serials, "#primary-serial-production-date")
    assert has_element?(serials, "#primary-serial-expiry-date")
    assert has_element?(serials, "#manufacturer-serials [phx-hook=DataMatrix]")
    assert has_element?(serials, "#export-batch-serials")
    assert has_element?(serials, "#manufacturer-serial-0001", "(17)")
    assert has_element?(serials, "#manufacturer-serial-0003")

    csv =
      conn
      |> get(~p"/manufacturer/products/#{product.gtin}/batches/#{batch.batch_no}/serials/export")
      |> response(200)

    assert csv =~ "#{product.gtin},#{batch.batch_no},"
    assert csv =~ ",0003\r\n"

    {:ok, ssccs, _html} = live(conn, ~p"/manufacturer/products/#{product.gtin}/ssccs")
    assert has_element?(ssccs, "#manufacturer-sscc-empty-state")
  end

  test "packs selected unpacked serials into a new shipper SSCC", %{conn: conn} do
    %{organization: organization, user: user, product: product} = manufacturer_session(conn)
    batch = manufacturer_batch_fixture(organization.id, product.id)

    assert {:ok, %{serials: [_, _, _]}} =
             Manufacturing.generate_primary_serials(
               organization.id,
               product,
               %{
                 "batch_no" => batch.batch_no,
                 "production_date" => Date.to_iso8601(batch.production_date),
                 "expiry_date" => Date.to_iso8601(batch.expiry_date)
               },
               3,
               manufacturer_session_gln(user)
             )

    conn = log_in_user(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/manufacturer/products/#{product.gtin}/serials")

    lv |> element("#open-pack-serials") |> render_click()

    assert has_element?(lv, "#pack-serials-panel")
    assert has_element?(lv, "#pack-serial-0001")
    assert has_element?(lv, "#pack-selected-count", "3")

    lv |> element("#pack-serial-0002") |> render_click()
    assert has_element?(lv, "#pack-selected-count", "2")

    lv |> element("#pack_to_gln_search") |> render_keyup(%{"value" => "Afya Test"})
    render_async(lv)
    lv |> element("#pack-to-gln-0614141000784") |> render_click()

    assert {:error, {:live_redirect, %{to: "/manufacturer/sscc/" <> _}}} =
             lv
             |> form("#pack-serials-form", %{
               "pack" => %{
                 "from_gln" => manufacturer_session_gln(user),
                 "order_number" => "PO-77"
               }
             })
             |> render_submit()

    request =
      Enum.find(
        ThamaniDawa.GS1.MemberApiStub.shipper_sscc_requests(),
        &(&1["barcode"] == product.gtin)
      )

    assert request["serials"] == ["0001", "0003"]
    assert request["to"] == %{"gln" => "0614141000784"}
    assert request["order_number"] == "PO-77"

    assert [%{sscc: shipper}] = Manufacturing.list_sscc_groups(organization.id, product.id)
    assert shipper.batch == batch.batch_no
    assert shipper.count_of_trade_items == 2
    assert shipper.to_gln == "0614141000784"

    packed =
      organization.id
      |> Manufacturing.list_serials(batch.id)
      |> Enum.filter(&(&1.manufacturer_shipper_sscc_id == shipper.id))
      |> Enum.map(& &1.serial)

    assert packed == ["0001", "0003"]

    # Packed serials no longer show up as candidates.
    assert {:ok, ["0002"]} =
             Manufacturing.fetch_unpacked_serials(organization.id, product.gtin, batch.batch_no)

    assert shipper.packed_serials == ["0001", "0003"]

    # The batch page lists the new shipper and tags each packed serial.
    {:ok, lv, _html} =
      live(conn, ~p"/manufacturer/products/#{product.gtin}/serials?batch=#{batch.batch_no}")

    assert has_element?(lv, "#batch-shipper-#{shipper.id}")
    assert has_element?(lv, "#batch-shipper-serials-#{shipper.id}")
    assert has_element?(lv, "#serial-sscc-0001")
    assert has_element?(lv, "#serial-sscc-0003")
    assert has_element?(lv, "#serial-unpacked-0002")
  end

  defp manufacturer_session_gln(user) do
    ThamaniDawa.Sites.get_site!(user.organization_id, user.current_site_id).gln
  end
end
