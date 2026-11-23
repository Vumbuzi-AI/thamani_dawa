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

    request =
      Enum.find(ThamaniDawa.GS1.MemberApiStub.serial_requests(), &(&1["barcode"] == product.gtin))

    assert request["shipper_qty"] == 6
    assert request["from"] == %{"gln" => site.gln}
    assert request["to"] == %{"gln" => site.gln}

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

  test "make-to-order path mints shipper SSCCs split across the primary serials", %{
    conn: conn
  } do
    %{organization: organization, site: site, user: user, product: product} =
      manufacturer_session(conn)

    other_facility =
      manufacturing_site_fixture(organization.id, %{
        name: "Secondary Plant",
        address: "2 Manufacturing Way"
      })

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

    assert has_element?(lv, "#serial_generation_to_gln-cb")

    assert has_element?(
             lv,
             "#serial_generation_to_gln-cb[data-options*='#{site.name}']"
           )

    refute has_element?(
             lv,
             "#serial_generation_to_gln-cb[data-options*='Secondary Plant']"
           )

    lv
    |> form("#manufacturer-serial-generation-form", %{
      "serial_generation" => %{"to_gln" => site.gln}
    })
    |> render_change()

    render_async(lv)

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
    assert has_element?(serials, "#serial-batch-#{batch.id}")
    assert has_element?(serials, "#manufacturer-serials [phx-hook=DataMatrix]")
    assert has_element?(serials, "#export-batch-serials")

    {:ok, ssccs, _html} = live(conn, ~p"/manufacturer/products/#{product.gtin}/ssccs")
    assert has_element?(ssccs, "#manufacturer-sscc-empty-state")
  end

  defp manufacturer_session_gln(user) do
    ThamaniDawa.Sites.get_site!(user.organization_id, user.current_site_id).gln
  end
end
