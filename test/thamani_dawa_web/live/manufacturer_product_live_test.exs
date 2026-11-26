defmodule ThamaniDawaWeb.ManufacturerProductLiveTest do
  # The GS1 stub is a shared named Agent; keep these tests sequential so one
  # test's directory fixtures cannot overwrite another's search results.
  use ThamaniDawaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    ThamaniDawa.GS1.MemberApiStub.reset()
    :ok
  end

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.ManufacturerFixtures

  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Manufacturing.ShipperSscc
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Repo

  defp allow_stock_serialization(organization) do
    {:ok, updated} =
      Organizations.update_organization_settings(organization, %{
        stock_serialization_enabled: true
      })

    updated
  end

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

    ThamaniDawa.GS1.MemberApiStub.put_products([
      %{
        "gtin" => product.gtin,
        "name" => product.name,
        "description" => product.description,
        "serial_count" => 0,
        "sscc_count" => 0
      }
    ])

    conn = log_in_user(conn, user)

    {:ok, lv, html} = live(conn, ~p"/manufacturer/products")

    assert html =~ "Products"
    assert has_element?(lv, "#manufacturer-products", product.gtin)
    assert has_element?(lv, "#manufacturer-products", product.name)
    # No serials yet: Generate serials only. View serials appears once a batch exists.
    refute has_element?(lv, "#product-#{product.id}-serials")
    assert has_element?(lv, "#product-#{product.id}-ssccs")
    assert has_element?(lv, "#product-#{product.id}-add-serial", "Generate serials")
    refute has_element?(lv, "#manufacturer-number-generated")
    refute has_element?(lv, "#manufacturer-maximum")
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
    render_async(lv)

    assert has_element?(lv, "#product-#{product.id}-serial-count", "17")
    assert has_element?(lv, "#product-#{product.id}-serials", "View serials")
    assert has_element?(lv, "#product-#{product.id}-add-serial", "Generate serials")
    assert has_element?(lv, "#product-#{product.id}-sscc-count", "3")
    refute has_element?(lv, "#manufacturer-number-generated")
  end

  test "filters by serials and shows the empty and no-match states", %{conn: conn} do
    %{user: user, product: product} = manufacturer_session(conn)

    ThamaniDawa.GS1.MemberApiStub.put_products([
      %{
        "gtin" => product.gtin,
        "name" => product.name,
        "description" => product.description,
        "serial_count" => 0,
        "sscc_count" => 0
      }
    ])

    {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/manufacturer/products?serials=with")

    refute has_element?(lv, "#manufacturer-product-#{product.id}")
    assert has_element?(lv, "#manufacturer-products-empty", "Nothing matches")

    {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/manufacturer/products?serials=none")
    assert has_element?(lv, "#manufacturer-product-#{product.id}")
    assert has_element?(lv, "#product-#{product.id}-open[href*='return_to']")
  end

  test "uses the GS1 catalogue and excludes products that only exist locally", %{conn: conn} do
    %{organization: organization, user: user, product: local_only} = manufacturer_session(conn)
    remote_gtin = "6164005056692"

    ThamaniDawa.GS1.MemberApiStub.put_products([
      %{
        "gtin" => remote_gtin,
        "name" => "Western",
        "description" => "Loaded from GS1",
        "serial_count" => 4,
        "sscc_count" => 1
      }
    ])

    {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/manufacturer/products")

    remote = Manufacturing.get_product_by_gtin!(organization.id, remote_gtin)

    assert has_element?(lv, "#manufacturer-product-#{remote.id}", "Western")
    assert has_element?(lv, "#product-#{remote.id}-serial-count", "4")
    refute has_element?(lv, "#manufacturer-product-#{local_only.id}")
  end

  test "has no add-product flow; products come from GS1", %{conn: conn} do
    %{user: user} = manufacturer_session(conn)
    {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/manufacturer/products")

    refute has_element?(lv, "#add-manufacturer-product")
    assert has_element?(lv, "#sync-manufacturer-products")
  end

  test "organization settings enable stock serialization explicitly", %{conn: conn} do
    organization = manufacturer_organization_fixture()
    site = manufacturing_site_fixture(organization.id)

    user =
      staff_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        role: :admin
      })

    refute Organizations.stock_serialization_enabled?(organization)
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, ~p"/manufacturer/settings")

    assert has_element?(view, "#organization-stock-serialization-enabled")
    refute has_element?(view, "#organization-stock-serialization-enabled[checked]")

    view
    |> form("#distributor-gs1-settings-form", %{
      "organization" => %{"stock_serialization_enabled" => "true"}
    })
    |> render_submit()

    assert Organizations.stock_serialization_enabled?(
             Organizations.get_organization!(organization.id)
           )

    assert has_element?(view, "#organization-stock-serialization-enabled[checked]")
  end

  test "serial wizard defaults to order-only when stock serialization is disabled", %{conn: conn} do
    %{organization: organization, user: user, product: product} = manufacturer_session(conn)

    refute Organizations.stock_serialization_enabled?(organization)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/manufacturer/products/#{product.gtin}/serials/new")

    lv
    |> form("#manufacturer-serial-generation-form", %{
      "serial_generation" => %{
        "batch_no" => "LOT-2026-ORDER-ONLY",
        "production_date" => "2026-11-20",
        "expiry_date" => "2027-11-20",
        "primary_quantity" => "4",
        "shipper_quantity" => "2"
      }
    })
    |> render_submit()

    assert has_element?(lv, "#serial-generation-order-only-note")
    assert has_element?(lv, ~s(input[name="serial_generation[order_intent]"][value="order"]))
    refute has_element?(lv, "#serial-generation-order-intent")
    refute has_element?(lv, "#serial-generation-order-intent-stock")
    assert has_element?(lv, "#serial-generation-order-number")
    assert has_element?(lv, "#serial-generation-to-gln-combobox")
    refute has_element?(lv, "#serial-wizard-mode-stock")

    # A crafted stock submission bypasses the hidden radio and is forced back
    # to order mode, so it cannot skip the genuine PO/destination requirement.
    render_submit(
      element(lv, "#manufacturer-serial-generation-form"),
      %{"serial_generation" => %{"order_intent" => "stock"}}
    )

    assert has_element?(lv, "#serial-generation-order-number")
    assert has_element?(lv, "#serial-generation-to-gln-combobox")
    assert Manufacturing.list_batches(organization.id, product.id) == []
  end

  test "two-step wizard serializes stock without allocating an SSCC", %{conn: conn} do
    %{organization: organization, site: site, user: user, product: product} =
      manufacturer_session(conn)

    organization = allow_stock_serialization(organization)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/manufacturer/products/#{product.gtin}/serials/new")

    assert has_element?(lv, "#serial-wizard-product", product.gtin)
    assert has_element?(lv, "#manufacturer-serial-modal", "Generate serials")
    assert has_element?(lv, "#serial-wizard-subtitle", "Batch details")
    assert has_element?(lv, "#serial-wizard-step-batch.is-current")
    assert has_element?(lv, "#manufacturer-serial-generation-form", "Batch number")
    assert has_element?(lv, "#serial-generation-facility-summary", site.name)
    assert has_element?(lv, "#serial-generation-facility-summary", site.gln)
    assert has_element?(lv, "#serial-generation-facility-summary", site.address)
    refute has_element?(lv, ~s(input[name="serial_generation[from_gln]"]))
    refute has_element?(lv, ~s(input[name="serial_generation[from_company_name]"]))
    refute has_element?(lv, ~s(input[name="serial_generation[from_address]"]))
    refute has_element?(lv, "#serial-wizard-mode-stock")
    refute has_element?(lv, "#serial-wizard-mode-order")
    # Dates use the TD date picker, never the browser's native calendar.
    assert has_element?(lv, ~s(.td-dp [data-dp-input][name="serial_generation[production_date]"]))
    assert has_element?(lv, ~s(.td-dp [data-dp-input][name="serial_generation[expiry_date]"]))
    refute has_element?(lv, ~s(input[type="date"]))

    lv
    |> form("#manufacturer-serial-generation-form", %{
      "serial_generation" => %{
        "batch_no" => "LOT-2026-11",
        "production_date" => "2026-11-20",
        "expiry_date" => "2027-11-20",
        "primary_quantity" => "20",
        "shipper_quantity" => "5"
      }
    })
    |> render_submit()

    assert has_element?(lv, "#serial-wizard-subtitle", "Order details")
    assert has_element?(lv, "#serial-wizard-step-order.is-current")
    assert has_element?(lv, "#serial-wizard-prev", "Back")
    assert has_element?(lv, "#serial-generation-order-intent-stock")
    assert has_element?(lv, "#serial-generation-summary", "4")
    assert has_element?(lv, "#serial-wizard-submit", "Generate serials")

    lv
    |> form("#manufacturer-serial-generation-form", %{
      "serial_generation" => %{"order_intent" => "stock"}
    })
    |> render_change()

    refute has_element?(lv, "#serial-generation-order-number")
    refute has_element?(lv, "#serial-generation-to-gln-combobox")
    refute has_element?(lv, ~s(input[name="serial_generation[from_gln]"]))

    expected_path = "/manufacturer/products/#{product.gtin}/serials?batch=LOT-2026-11"

    assert {:error, {:live_redirect, %{to: ^expected_path}}} =
             lv
             |> form("#manufacturer-serial-generation-form", %{
               "serial_generation" => %{"order_intent" => "stock"}
             })
             |> render_submit()

    operation =
      ThamaniDawa.Manufacturing.Operations.generation_status_for_product(
        organization.id,
        product.id,
        "LOT-2026-11"
      )

    assert {:ok, _allocated} =
             ThamaniDawa.Manufacturing.Operations.allocate_identifiers(operation.id)

    [{batch, 20}] = Manufacturing.list_batches(organization.id, product.id)
    assert [serial | _] = Manufacturing.list_serials(organization.id, batch.id)
    assert serial.serial != nil
    assert Manufacturing.list_sscc_groups(organization.id, product.id) == []
    assert batch.pack_quantity == 20
    assert batch.packs_per_shipper == 5
    assert batch.expected_shipper_count == 4
    assert batch.from_gln == site.gln
    assert batch.from_company_name == site.name
    assert batch.from_address == site.address
    assert batch.order_number in [nil, ""]
    assert batch.to_gln in [nil, ""]
    assert batch.shipper_preparation_method == nil

    request =
      Enum.find(ThamaniDawa.GS1.MemberApiStub.serial_requests(), &(&1["barcode"] == product.gtin))

    assert request["create_shippers"] == false
    assert request["trade_item_qty"] == "20"
    refute Map.has_key?(request, "shipper_qty")
    refute Map.has_key?(request, "from")
    refute Map.has_key?(request, "to")
    refute Map.has_key?(request, "order_number")
    assert ThamaniDawa.GS1.MemberApiStub.shipper_sscc_requests() == []

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

  test "shows newly created batches first with their creation timestamps", %{conn: conn} do
    %{organization: organization, user: user, product: product} = manufacturer_session(conn)

    assert {:ok, _result} =
             Manufacturing.generate_primary_serials(
               organization.id,
               product,
               %{
                 "batch_no" => "OLDER-BATCH",
                 "production_date" => "2026-11-22",
                 "expiry_date" => "2027-11-22"
               },
               1,
               manufacturer_session_gln(user)
             )

    assert {:ok, _result} =
             Manufacturing.generate_primary_serials(
               organization.id,
               product,
               %{
                 "batch_no" => "NEWEST-BATCH",
                 "production_date" => "2026-01-01",
                 "expiry_date" => "2027-01-01"
               },
               1,
               manufacturer_session_gln(user)
             )

    assert {:ok, [newest, older]} =
             Manufacturing.fetch_product_batches(organization.id, product.gtin)

    assert newest.batch_no == "NEWEST-BATCH"
    assert older.batch_no == "OLDER-BATCH"
    assert newest.created_at

    {:ok, view, _html} =
      live(log_in_user(conn, user), ~p"/manufacturer/products/#{product.gtin}/serials")

    assert has_element?(view, "#selected-serial-batch", "NEWEST-BATCH")

    assert has_element?(
             view,
             "#serial-batch-created-at-NEWEST-BATCH",
             ThamaniDawaWeb.TimeFormat.datetime(newest.created_at)
           )
  end

  test "serials page shows one full-width empty state when a product has no batches", %{
    conn: conn
  } do
    %{user: user, product: product} = manufacturer_session(conn)
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, ~p"/manufacturer/products/#{product.gtin}/serials")

    assert has_element?(view, "#manufacturer-serial-batches-empty #serial-batches-empty")
    refute has_element?(view, "#empty-generate-serials")
    refute has_element?(view, "#batches-generate-serials")
    refute has_element?(view, "#manufacturer-serial-batches")
  end

  test "two-step wizard records order details without minting shipper SSCCs", %{
    conn: conn
  } do
    %{organization: organization, site: site, user: user, product: product} =
      manufacturer_session(conn)

    destination_gln = "0614141000784"

    ThamaniDawa.GS1.MemberApiStub.put_glns([
      %{
        "gln" => destination_gln,
        "description" => "Afya Test Warehouse",
        "address" => "Nairobi, Kenya",
        "location" => "Nairobi",
        "company" => "Afya Test Org"
      },
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

    lv
    |> form("#manufacturer-serial-generation-form", %{
      "serial_generation" => %{
        "batch_no" => "LOT-2026-ORDER",
        "production_date" => "2026-11-20",
        "expiry_date" => "2027-11-20",
        "primary_quantity" => "8",
        "shipper_quantity" => "2"
      }
    })
    |> render_submit()

    assert has_element?(lv, "#serial-wizard-subtitle", "Order details")
    assert has_element?(lv, "#serial-generation-summary", "4")
    refute has_element?(lv, ~s(input[name="serial_generation[from_gln]"]))

    lv
    |> form("#manufacturer-serial-generation-form", %{
      "serial_generation" => %{"order_intent" => "order"}
    })
    |> render_change()

    assert has_element?(lv, "#serial-generation-order-number")
    assert has_element?(lv, "#serial-generation-to-gln-combobox")

    assert has_element?(lv, ~s(input[name="serial_generation[order_intent]"][value="order"]))
    refute has_element?(lv, "#serial-generation-order-intent-stock")
    refute has_element?(lv, "#serial-generation-to-gln-results")

    lv
    |> element("#serial_generation_to_gln_search")
    |> render_keyup(%{"value" => "c"})

    assert has_element?(lv, "#serial-generation-to-gln-search-hint")

    lv
    |> element("#serial_generation_to_gln_search")
    |> render_keyup(%{"value" => destination_gln})

    render_async(lv)

    assert has_element?(lv, "#serial-generation-to-gln-results")
    assert has_element?(lv, "#serial-generation-to-gln-#{destination_gln}", "Afya Test Org")

    lv
    |> element("#serial-generation-to-gln-#{destination_gln}")
    |> render_click()

    assert has_element?(
             lv,
             ~s(input[name="serial_generation[to_company_name]"][value="Afya Test Org"][readonly])
           )

    assert has_element?(
             lv,
             ~s(input[name="serial_generation[to_address]"][value="Nairobi, Kenya"][readonly])
           )

    expected_path = "/manufacturer/products/#{product.gtin}/serials?batch=LOT-2026-ORDER"

    assert {:error, {:live_redirect, %{to: ^expected_path}}} =
             lv
             |> form("#manufacturer-serial-generation-form", %{
               "serial_generation" => %{
                 "to_gln" => destination_gln,
                 "to_company_name" => "Untrusted submitted name",
                 "to_address" => "Untrusted submitted address",
                 "order_number" => "PO-2026-0142"
               }
             })
             |> render_submit()

    operation =
      ThamaniDawa.Manufacturing.Operations.generation_status_for_product(
        organization.id,
        product.id,
        "LOT-2026-ORDER"
      )

    assert {:ok, _allocated} =
             ThamaniDawa.Manufacturing.Operations.allocate_identifiers(operation.id)

    [{batch, 8}] = Manufacturing.list_batches(organization.id, product.id)

    assert batch.from_gln == site.gln
    assert batch.from_company_name == site.name
    assert batch.from_address == site.address
    assert batch.order_number == "PO-2026-0142"
    assert batch.to_gln == destination_gln
    assert batch.to_company_name == "Afya Test Org"
    assert batch.to_address == "Nairobi, Kenya"
    assert batch.pack_quantity == 8
    assert batch.packs_per_shipper == 2
    assert batch.expected_shipper_count == 4

    # Order metadata is recorded for later SSCC allocation, but this step still
    # creates only product serials.
    assert Manufacturing.list_sscc_groups(organization.id, product.id) == []
    assert length(Manufacturing.list_serials(organization.id, batch.id)) == 8
    assert ThamaniDawa.GS1.MemberApiStub.shipper_sscc_requests() == []

    request =
      Enum.find(ThamaniDawa.GS1.MemberApiStub.serial_requests(), &(&1["barcode"] == product.gtin))

    assert request["create_shippers"] == false
    refute Map.has_key?(request, "shipper_qty")
    refute Map.has_key?(request, "from")
    refute Map.has_key?(request, "to")
    refute Map.has_key?(request, "order_number")
  end

  test "serial and SSCC eye links open org-scoped drill-downs", %{conn: conn} do
    %{organization: organization, site: site, user: user, product: product} =
      manufacturer_session(conn)

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

    ThamaniDawa.GS1.MemberApiStub.put_glns([
      %{
        "gln" => "0614141000784",
        "description" => "Afya Test Org",
        "address" => "Nairobi, Kenya",
        "location" => "Nairobi",
        "company" => "Afya Test Org"
      }
    ])

    conn = log_in_user(conn, user)

    {:ok, serials, _html} = live(conn, ~p"/manufacturer/products/#{product.gtin}/serials")
    # Batches and serials come from the GS1 member API (stubbed here).
    assert has_element?(serials, "#serial-batch-#{batch.batch_no}", "3")
    assert has_element?(serials, "#primary-serial-batch-details")
    assert has_element?(serials, "#primary-serial-gtin", product.gtin)
    assert has_element?(serials, "#primary-serial-batch-number", batch.batch_no)

    assert has_element?(
             serials,
             "#primary-serial-batch-created-at",
             ThamaniDawaWeb.TimeFormat.datetime(batch.inserted_at)
           )

    assert has_element?(serials, "#primary-serial-production-date")
    assert has_element?(serials, "#primary-serial-expiry-date")

    assert has_element?(
             serials,
             "#serial-batch-created-at-#{batch.batch_no}",
             ThamaniDawaWeb.TimeFormat.datetime(batch.inserted_at)
           )

    # The batch shows ten serials at a time. View all serials sits in the
    # card header. The footer is the shared pager.
    assert has_element?(serials, "#serial-preview-card #view-all-serials", "View all serials")
    assert has_element?(serials, "#serial-preview-pager", "1 to 3 of 3 serials")
    refute has_element?(serials, "#serial-preview-more")
    assert has_element?(serials, "#serial-label-preview [phx-hook=DataMatrix]")
    assert has_element?(serials, "#serial-label-sample-datamatrix[data-gs1-text*='(17)']")
    assert has_element?(serials, "#export-batch-serials")

    assert has_element?(
             serials,
             "#prepare-batch-shippers[href^='/manufacturer/aggregations/batches/#{batch.id}/prepare?']",
             "Create shippers"
           )

    return_path = ~p"/manufacturer/products/#{product.gtin}/serials?batch=#{batch.batch_no}"

    {:ok, prepare, _html} =
      live(
        conn,
        ~p"/manufacturer/aggregations/batches/#{batch.id}/prepare?#{%{return_to: return_path}}"
      )

    assert has_element?(
             prepare,
             "#prepare-shippers-back[href='#{return_path}']",
             "Back to Batches"
           )

    assert has_element?(prepare, "h1", "Create shippers")
    assert has_element?(prepare, "#prepare-batch-number", batch.batch_no)
    assert has_element?(prepare, "#prepare-batch-gtin", product.gtin)
    assert has_element?(prepare, "#prepare-batch-serials", "3")
    assert has_element?(prepare, "#prepare-batch-packed", "0 of 3")
    assert has_element?(prepare, "#prepare-ship-from-name", organization.name)
    assert has_element?(prepare, "#prepare-shipment-parties", site.gln)
    assert has_element?(prepare, "#prepare-ship-to-name", "Destination not selected")
    assert has_element?(prepare, "#registry-shipper-setup-modal", "Set up shipper packing")
    assert has_element?(prepare, "#gs1-create-sscc-warning", "no destination GLN")
    refute has_element?(prepare, "#shipper-quantity-form")
    assert has_element?(prepare, "#prepare-shipper-quantity", "Not set")
    assert has_element?(prepare, "#prepare-batch-shippers-count", "0 created")
    refute has_element?(prepare, "#view-created-shippers")
    assert has_element?(prepare, "#shipper-quantity-warning", "Set the units per shipper")
    assert has_element?(prepare, "#select-all-unpacked[disabled]", "Set quantity")
    assert has_element?(prepare, "#serial-shipper-selection")
    assert has_element?(prepare, "#create-shipper-from-serials", "Create shipper")
    assert has_element?(prepare, "#prepare-shipper-labels")
    assert has_element?(prepare, "#prepare-shippers-empty")
    refute has_element?(prepare, "#print-all-shipper-labels")

    prepare
    |> element("#registry-setup-to-gln-search")
    |> render_keyup(%{"value" => "0614141000784"})

    render_async(prepare)

    prepare
    |> element("#registry-setup-to-gln-0614141000784")
    |> render_click()

    prepare
    |> form("#registry-shipper-setup-form", %{
      "shipper_quantity" => %{"packs_per_shipper" => "3"}
    })
    |> render_submit()

    refute has_element?(prepare, "#registry-shipper-setup-modal")
    assert has_element?(prepare, "#prepare-ship-to-name", "Afya Test Org")
    assert has_element?(prepare, "#prepare-shipper-quantity", "3")
    assert has_element?(prepare, "#prepare-batch-shippers-count", "0 of 1 created")
    assert has_element?(prepare, "#change-registry-shipper-setup", "Change setup")
    assert has_element?(prepare, "#select-all-unpacked", "Select 3")
    assert Manufacturing.get_batch!(organization.id, batch.id).packs_per_shipper == 3
    assert Manufacturing.get_batch!(organization.id, batch.id).to_gln == "0614141000784"

    {:ok, refreshed, _html} =
      live(conn, ~p"/manufacturer/aggregations/batches/#{batch.id}/prepare")

    refute has_element?(refreshed, "#registry-shipper-setup-modal")
    assert has_element?(refreshed, "#prepare-ship-to-name", "Afya Test Org")
    assert has_element?(refreshed, "#prepare-shipper-quantity", "3")
    assert has_element?(refreshed, "#select-all-unpacked", "Select 3")

    refreshed |> element("#change-registry-shipper-setup") |> render_click()
    assert has_element?(refreshed, "#registry-shipper-setup-modal")

    refreshed
    |> element("#registry-shipper-setup-modal button[aria-label='Close']")
    |> render_click()

    refute has_element?(refreshed, "#registry-shipper-setup-modal")

    assert has_element?(serials, "#manufacturer-serials th", "Serial")
    assert has_element?(serials, "#manufacturer-serial-0001", "0001")
    refute has_element?(serials, "#manufacturer-serial-0001", "(01)")
    assert has_element?(serials, "#manufacturer-serial-0003")
    assert has_element?(serials, "#primary-serial-packed", "0 of 3")

    {:ok, detailed, _html} =
      live(conn, ~p"/manufacturer/products/#{product.gtin}/serials?batch=#{batch.batch_no}")

    assert has_element?(detailed, "#primary-serial-packs-per-shipper", "3")

    assert has_element?(serials, "#open-print-labels", "Print serial labels")
    refute has_element?(serials, "#print-batch-shipper-labels")

    serials |> element("#open-print-labels") |> render_click()
    assert has_element?(serials, "#print-labels-modal")
    assert has_element?(serials, "#print-batch-labels[phx-hook=PrintAllLabels]", "Print 3 labels")
    assert has_element?(serials, "#print-labels-sheet .printable-serial-label", "SN 0003")
    serials |> element("#cancel-print-labels") |> render_click()
    refute has_element?(serials, "#print-labels-modal")

    {:ok, view, _html} =
      live(
        conn,
        ~p"/manufacturer/products/#{product.gtin}/serials?batch=#{batch.batch_no}&view=serials&return_to=/manufacturer/products"
      )

    assert has_element?(view, "#view-serials-back[href*='batch=#{batch.batch_no}']")
    assert has_element?(view, "#view-serials-count", "3")
    assert has_element?(view, "#manufacturer-serial-0002", "0002")
    refute has_element?(view, "#manufacturer-serial-0002", "(01)")
    assert has_element?(view, "#manufacturer-serial-0002", batch.batch_no)

    view |> form("#manufacturer-serial-search", search: "nope") |> render_change()
    assert has_element?(view, "#view-serials-empty")

    csv =
      conn
      |> get(~p"/manufacturer/products/#{product.gtin}/batches/#{batch.batch_no}/serials/export")
      |> response(200)

    assert csv =~ "#{product.gtin},#{batch.batch_no},"
    assert csv =~ ",0003\r\n"

    {:ok, ssccs, _html} = live(conn, ~p"/manufacturer/products/#{product.gtin}/ssccs")
    assert has_element?(ssccs, "#manufacturer-sscc-empty-state")
  end

  test "create shippers works for a batch that only exists in GS1", %{conn: conn} do
    %{organization: organization, user: user, product: product} = manufacturer_session(conn)
    batch_no = "GS1-ONLY-1"

    ThamaniDawa.GS1.MemberApiStub.post_create_serials(%{
      "barcode" => product.gtin,
      "batch" => batch_no,
      "production" => "260101",
      "expiry" => "280101",
      "trade_item_qty" => 3,
      "create_shippers" => false
    })

    assert is_nil(
             Manufacturing.get_batch_by_product_and_no(organization.id, product.id, batch_no)
           )

    conn = log_in_user(conn, user)

    {:ok, serials, _html} =
      live(conn, ~p"/manufacturer/products/#{product.gtin}/serials?batch=#{batch_no}")

    refute has_element?(serials, "#export-batch-serials")
    assert has_element?(serials, "#prepare-batch-shippers", "Create shippers")
    assert has_element?(serials, "#open-print-labels", "Print serial labels")

    assert has_element?(
             serials,
             "#primary-serial-batch-created-at",
             "External"
           )

    assert has_element?(
             serials,
             "#prepare-batch-shippers[href^='/manufacturer/aggregations/prepare']"
           )

    {:ok, full_serials, _html} =
      live(
        conn,
        ~p"/manufacturer/products/#{product.gtin}/serials?batch=#{batch_no}&view=serials"
      )

    refute has_element?(full_serials, "#export-batch-serials")

    {:ok, prepare, _html} =
      live(
        conn,
        ~p"/manufacturer/aggregations/prepare?#{%{gtin: product.gtin, batch: batch_no}}"
      )

    assert has_element?(prepare, "h1", "Create shippers")
    assert has_element?(prepare, "#prepare-batch-number", batch_no)
    assert has_element?(prepare, "#prepare-ship-from-name", organization.name)
    assert has_element?(prepare, "#serial-row-gs1-1", "0001")
    assert has_element?(prepare, "#registry-shipper-setup-modal", "Set up shipper packing")
    refute has_element?(prepare, "#gs1-create-sscc-warning")

    prepare
    |> element("#registry-setup-to-gln-search")
    |> render_keyup(%{"value" => "0614141000784"})

    render_async(prepare)

    assert has_element?(
             prepare,
             "#registry-shipper-setup-modal #registry-setup-to-gln-0614141000784"
           )

    prepare
    |> element("#registry-setup-to-gln-0614141000784")
    |> render_click()

    assert has_element?(prepare, "#registry-setup-destination", "Afya Test Org")

    prepare
    |> form("#registry-shipper-setup-form", %{
      "shipper_quantity" => %{"packs_per_shipper" => "3"}
    })
    |> render_submit()

    refute has_element?(prepare, "#registry-shipper-setup-modal")
    assert has_element?(prepare, "#prepare-ship-to-name", "Afya Test Org")
    assert has_element?(prepare, "#change-registry-shipper-setup", "Change setup")
    assert has_element?(prepare, "#select-all-unpacked", "Select 3")

    prepare |> element("#select-all-unpacked") |> render_click()
    prepare |> element("#create-shipper-from-serials") |> render_click()

    {shippers, _by_serial} =
      Manufacturing.list_batch_shippers(organization.id, product.gtin, batch_no)

    assert [shipper] = shippers
    assert has_element?(prepare, "#prepared-shipper-#{shipper.id}")
    assert has_element?(prepare, "#prepare-batch-shippers-count", "1 of 1 created")

    assert has_element?(
             prepare,
             "button#view-created-shippers[phx-click]",
             "View shippers"
           )

    assert has_element?(
             prepare,
             "#print-all-shipper-labels[phx-hook=PrintAllLabels]",
             "Print all"
           )

    assert has_element?(
             prepare,
             "#prepare-printable-shipper-labels #batch-shipper-label-content-#{shipper.id}.printable-sscc-label"
           )

    assert has_element?(prepare, "#prepare-batch-packed", "3 of 3")
    refute has_element?(prepare, "#serial-shipper-selection")
    refute has_element?(prepare, "#no-unpacked-serials")

    assert has_element?(
             prepare,
             "#print-shipper-#{shipper.id}[phx-click='open_label']"
           )

    refute has_element?(prepare, "#shipper-label-modal")

    prepare |> element("#print-shipper-#{shipper.id}") |> render_click()

    assert has_element?(prepare, "#shipper-label-modal")
    assert has_element?(prepare, "#print-manufacturer-label")
    assert has_element?(prepare, "#prepared-shippers-table")

    prepare |> element("#shipper-label-modal button[aria-label='Close']") |> render_click()

    refute has_element?(prepare, "#shipper-label-modal")
    assert has_element?(prepare, "#prepared-shippers-table")
  end

  test "select button advances to the next shipper-sized group of unpacked serials", %{conn: conn} do
    %{organization: organization, user: user, product: product} = manufacturer_session(conn)

    batch =
      manufacturer_batch_fixture(organization.id, product.id, %{
        pack_quantity: 4,
        packs_per_shipper: 2,
        to_gln: "0614141000785"
      })

    assert {:ok, %{serials: [first, second, third, fourth]}} =
             Manufacturing.generate_primary_serials(
               organization.id,
               product,
               %{
                 "batch_no" => batch.batch_no,
                 "production_date" => Date.to_iso8601(batch.production_date),
                 "expiry_date" => Date.to_iso8601(batch.expiry_date)
               },
               4,
               manufacturer_session_gln(user)
             )

    conn = log_in_user(conn, user)

    {:ok, lv, _html} =
      live(conn, ~p"/manufacturer/aggregations/batches/#{batch.id}/prepare")

    assert has_element?(lv, "#select-all-unpacked", "Select 2")

    lv |> element("#select-all-unpacked") |> render_click()
    assert has_element?(lv, "#select-serial-#{first.id}[checked]")
    assert has_element?(lv, "#select-serial-#{second.id}[checked]")
    refute has_element?(lv, "#select-serial-#{third.id}[checked]")
    refute has_element?(lv, "#select-serial-#{fourth.id}[checked]")

    lv |> element("#select-all-unpacked") |> render_click()
    refute has_element?(lv, "#select-serial-#{first.id}[checked]")
    refute has_element?(lv, "#select-serial-#{second.id}[checked]")
    assert has_element?(lv, "#select-serial-#{third.id}[checked]")
    assert has_element?(lv, "#select-serial-#{fourth.id}[checked]")

    lv |> element("#create-shipper-from-serials") |> render_click()

    {shippers, _by_serial} =
      Manufacturing.list_batch_shippers(organization.id, product.gtin, batch.batch_no)

    shipper = hd(shippers)

    assert has_element?(lv, "#serial-row-#{first.id}")
    assert has_element?(lv, "#serial-row-#{second.id}")
    refute has_element?(lv, "#serial-row-#{third.id}")
    refute has_element?(lv, "#serial-row-#{fourth.id}")

    lv |> element("#contents-shipper-#{shipper.id}") |> render_click()
    assert has_element?(lv, "#prepare-shipper-contents-modal")
    assert has_element?(lv, "#prepare-shipper-content-#{shipper.id}-#{third.serial}")
    assert has_element?(lv, "#prepare-shipper-content-#{shipper.id}-#{fourth.serial}")
  end

  test "packs selected unpacked serials into a new shipper SSCC", %{conn: conn} do
    %{organization: organization, user: user, product: product} = manufacturer_session(conn)
    batch = manufacturer_batch_fixture(organization.id, product.id)

    ThamaniDawa.GS1.MemberApiStub.put_glns([
      %{
        "gln" => "0614141000784",
        "description" => "Test Licensee",
        "address" => "Nairobi, Kenya",
        "location" => "Nairobi",
        "company" => "Afya Test Org"
      }
    ])

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

    {:ok, lv, _html} =
      live(
        conn,
        ~p"/manufacturer/products/#{product.gtin}/serials/pack?batch=#{batch.batch_no}"
      )

    assert has_element?(lv, "#pack-serials-panel")
    assert has_element?(lv, "#pack-serial-0001")
    assert has_element?(lv, "#pack-selected-count", "3")

    lv |> element("#pack-serial-0002") |> render_click()
    assert has_element?(lv, "#pack-selected-count", "2")

    lv |> element("#pack-next") |> render_click()
    assert has_element?(lv, "#pack-parties-form")

    lv |> element("#pack_to_gln_search") |> render_keyup(%{"value" => "Afya Test"})
    render_async(lv)
    lv |> element("#pack-to-gln-0614141000784") |> render_click()

    lv
    |> form("#pack-parties-form", %{"pack" => %{"order_number" => "PO-77"}})
    |> render_change()

    lv |> element("#pack-next") |> render_click()
    assert has_element?(lv, "#pack-serials-form")

    lv
    |> form("#pack-serials-form", %{"pack" => %{}})
    |> render_submit()

    assert has_element?(lv, "#pack-result")
    assert has_element?(lv, "#pack-result-view[href^='/manufacturer/sscc/']")

    request =
      Enum.find(
        ThamaniDawa.GS1.MemberApiStub.shipper_sscc_requests(),
        &(&1["barcode"] == product.gtin)
      )

    assert request["serials"] == ["0001", "0003"]
    assert request["to"] == %{"gln" => "0614141000784"}
    assert request["order_number"] == "PO-77"

    expected_description =
      if product.description in [nil, ""], do: product.name, else: product.description

    assert request["material_description"] == expected_description

    assert [%{sscc: shipper, serial_count: 2, serials: ["0001", "0003"]}] =
             Manufacturing.list_sscc_groups(organization.id, product.id)

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

    # From/To details and order number are saved for the label.
    site = ThamaniDawa.Sites.get_site!(user.organization_id, user.current_site_id)
    assert shipper.from_company_name == site.name
    assert shipper.from_address == site.address
    assert shipper.to_company_name not in [nil, ""]
    assert shipper.order_number == "PO-77"

    {:ok, label, _html} = live(conn, ~p"/manufacturer/sscc/#{shipper.id}/label")
    assert has_element?(label, "#sscc-label-from-#{shipper.id}", site.name)
    assert has_element?(label, "#sscc-label-to-#{shipper.id}", shipper.to_company_name)
    assert has_element?(label, "#sscc-label-quantity-#{shipper.id}", "2")
    assert has_element?(label, "#sscc-label-order-number-#{shipper.id}", "PO-77")

    # The batch page lists the new shipper and tags each packed serial.
    {:ok, lv, _html} =
      live(conn, ~p"/manufacturer/products/#{product.gtin}/serials?batch=#{batch.batch_no}")

    assert has_element?(lv, "#batch-shipper-#{shipper.id}")
    assert has_element?(lv, "#batch-shipper-serials-#{shipper.id}")

    assert has_element?(
             lv,
             "#print-batch-shipper-labels[phx-hook=PrintAllLabels]",
             "Print shipper labels"
           )

    assert has_element?(
             lv,
             "#batch-printable-shipper-labels #batch-product-shipper-label-content-#{shipper.id}.printable-sscc-label"
           )

    assert has_element?(lv, "#serial-sscc-0001")
    assert has_element?(lv, "#serial-sscc-0003")
    assert has_element?(lv, "#serial-unpacked-0002")
    # One serial is still unpacked, so mobile aggregation preparation stays available.
    assert has_element?(lv, "#prepare-batch-shippers", "Create shippers")
    refute has_element?(lv, "#batch-fully-packed")

    # Once the last serial is packed, the button gives way to a badge.
    gs1_batch = %{
      batch_no: batch.batch_no,
      production_date: batch.production_date,
      expiry_date: batch.expiry_date
    }

    assert {:ok, packed} =
             Manufacturing.pack_serials_into_shipper(
               organization.id,
               product,
               gs1_batch,
               ["0002"],
               %{"from_gln" => manufacturer_session_gln(user), "to_gln" => "0614141000784"}
             )

    # Packing only creates the shipper and its Pack event. The shipment and
    # Ship event come later, from the shipments page.
    assert Manufacturing.list_shipments(organization.id) == []

    refute Enum.any?(
             ThamaniDawa.Epcis.Outbox.list_events(organization.id),
             &(&1.event_type == "shipping")
           )

    assert Enum.any?(Manufacturing.list_available_ssccs(organization.id), &(&1.id == packed.id))

    {:ok, lv, _html} =
      live(conn, ~p"/manufacturer/products/#{product.gtin}/serials?batch=#{batch.batch_no}")

    assert has_element?(lv, "#batch-fully-packed")
    refute has_element?(lv, "#prepare-batch-shippers")
  end

  test "label resolves From/To names from GLNs for older shippers", %{conn: conn} do
    %{organization: organization, user: user, product: product} = manufacturer_session(conn)
    site = ThamaniDawa.Sites.get_site!(user.organization_id, user.current_site_id)

    ThamaniDawa.GS1.MemberApiStub.put_glns([
      %{
        "gln" => "0614141000784",
        "description" => "Test Licensee",
        "address" => "Nairobi, Kenya",
        "location" => "Nairobi",
        "company" => "Afya Test Org"
      },
      %{
        "gln" => site.gln,
        "description" => site.name,
        "address" => site.address,
        "location" => "Nairobi",
        "company" => site.name
      }
    ])

    shipper =
      ThamaniDawa.Repo.insert!(%ThamaniDawa.Manufacturing.ShipperSscc{
        organization_id: organization.id,
        code: "261640050560000999",
        gtin: product.gtin,
        batch: "B1",
        from_gln: site.gln,
        to_gln: "0614141000784",
        count_of_trade_items: 5
      })

    {:ok, label, _html} =
      live(log_in_user(conn, user), ~p"/manufacturer/sscc/#{shipper.id}/label")

    assert has_element?(label, "#sscc-label-from-#{shipper.id}", site.name)
    gs = <<29>>
    assert has_element?(label, "#sscc-label-barcode-#{shipper.id}[data-barcode^='#{gs}00']")
    assert has_element?(label, "#sscc-label-barcode-#{shipper.id}[data-barcode*='#{gs}01']")
    refute has_element?(label, "#sscc-label-barcode-#{shipper.id}[data-barcode*='#{gs}02']")

    saved = ThamaniDawa.Repo.get!(ThamaniDawa.Manufacturing.ShipperSscc, shipper.id)
    assert saved.from_company_name == site.name
    assert saved.to_company_name not in [nil, ""]
    assert has_element?(label, "#sscc-label-to-#{shipper.id}", saved.to_company_name)
    assert has_element?(label, "#sscc-label-content-#{shipper.id}")
    assert has_element?(label, "#sscc-label-quantity-#{shipper.id}", "5")
  end

  test "serial generation redirects to the product serials page and updates when allocation completes",
       %{conn: conn} do
    %{organization: organization, user: user, product: product} = manufacturer_session(conn)
    organization = allow_stock_serialization(organization)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/manufacturer/products/#{product.gtin}/serials/new")

    lv
    |> form("#manufacturer-serial-generation-form", %{
      "serial_generation" => %{
        "batch_no" => "LOT-2026-GEN",
        "production_date" => "2026-11-20",
        "expiry_date" => "2027-11-20",
        "primary_quantity" => "4",
        "shipper_quantity" => "2"
      }
    })
    |> render_submit()

    assert has_element?(lv, "#serial-generation-order-intent label.td-option .td-oc-rd")
    assert has_element?(lv, "#serial-generation-order-intent label.td-option.is-selected")

    expected_path = "/manufacturer/products/#{product.gtin}/serials?batch=LOT-2026-GEN"

    assert {:error, {:live_redirect, %{to: ^expected_path}}} =
             lv
             |> form("#manufacturer-serial-generation-form", %{
               "serial_generation" => %{"order_intent" => "stock"}
             })
             |> render_submit()

    {:ok, serials_lv, _html} = live(conn, expected_path)
    assert has_element?(serials_lv, "#serial-allocation-pending", "LOT-2026-GEN")
    refute has_element?(serials_lv, "#serial-batches-empty")

    op =
      ThamaniDawa.Manufacturing.Operations.generation_status_for_product(
        organization.id,
        product.id,
        "LOT-2026-GEN"
      )

    assert {:ok, _updated} = ThamaniDawa.Manufacturing.Operations.allocate_identifiers(op.id)
    render_async(serials_lv)

    assert has_element?(serials_lv, "#selected-serial-batch", "LOT-2026-GEN")
    refute has_element?(serials_lv, "#serial-allocation-pending")

    # Arming SSCC allocation reuses the operation, but must not resurrect the
    # serial-generation banner after product serials are already complete.
    operation =
      ThamaniDawa.Repo.get!(ThamaniDawa.Manufacturing.GenerationOperation, op.id)

    operation
    |> Ecto.Changeset.change(status: "allocating", sscc_allocation_status: "pending")
    |> ThamaniDawa.Repo.update!()

    {:ok, sscc_phase_lv, _html} = live(conn, expected_path)
    refute has_element?(sscc_phase_lv, "#serial-allocation-pending")
    refute has_element?(sscc_phase_lv, "#serial-allocation-error")
  end

  test "reconciles an uncertain serial check from the serials page", %{conn: conn} do
    %{organization: organization, user: user, product: product} = manufacturer_session(conn)
    organization = allow_stock_serialization(organization)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/manufacturer/products/#{product.gtin}/serials/new")

    lv
    |> form("#manufacturer-serial-generation-form", %{
      "serial_generation" => %{
        "batch_no" => "LOT-2026-GS1-CHECK",
        "production_date" => "2026-11-20",
        "expiry_date" => "2027-11-20",
        "primary_quantity" => "4",
        "shipper_quantity" => "2"
      }
    })
    |> render_submit()

    expected_path = "/manufacturer/products/#{product.gtin}/serials?batch=LOT-2026-GS1-CHECK"

    assert {:error, {:live_redirect, %{to: ^expected_path}}} =
             lv
             |> form("#manufacturer-serial-generation-form", %{
               "serial_generation" => %{"order_intent" => "stock"}
             })
             |> render_submit()

    {:ok, serials_lv, _html} = live(conn, expected_path)

    op =
      ThamaniDawa.Manufacturing.Operations.generation_status_for_product(
        organization.id,
        product.id,
        "LOT-2026-GS1-CHECK"
      )

    ThamaniDawa.GS1.MemberApiStub.fail_next(:unavailable)
    assert {:ok, _uncertain} = ThamaniDawa.Manufacturing.Operations.allocate_identifiers(op.id)
    render_async(serials_lv)

    assert has_element?(
             serials_lv,
             "#serial-allocation-error",
             "couldn't confirm whether GS1 created"
           )

    assert has_element?(serials_lv, "#reconcile-serial-allocation", "Check with GS1")

    serials_lv
    |> element("#reconcile-serial-allocation")
    |> render_click()

    assert has_element?(serials_lv, "#selected-serial-batch", "LOT-2026-GS1-CHECK")
    refute has_element?(serials_lv, "#serial-allocation-error")
    refute has_element?(serials_lv, "#reconcile-serial-allocation")
  end

  test "print label opens and closes the modal without leaving the SSCC list", %{conn: conn} do
    %{organization: organization, user: user, product: product} = manufacturer_session(conn)

    sscc =
      Repo.insert!(%ShipperSscc{
        organization_id: organization.id,
        code: "061600000000000018",
        gtin: product.gtin,
        batch: "LIST-LABEL",
        count_of_trade_items: 3
      })

    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/manufacturer/products/#{product.gtin}/ssccs")

    assert has_element?(lv, "#shipper-row-#{sscc.id}")
    refute has_element?(lv, "#shipper-label-modal")

    lv |> element("#print-label-#{sscc.id}") |> render_click()

    assert has_element?(lv, "#shipper-label-modal")
    assert has_element?(lv, "#print-manufacturer-label")
    assert has_element?(lv, "#manufacturer-product-ssccs")
    assert has_element?(lv, "#ssccs-back")

    lv |> element("#shipper-label-modal button[aria-label='Close']") |> render_click()

    refute has_element?(lv, "#shipper-label-modal")
    assert has_element?(lv, "#manufacturer-product-ssccs")
  end

  defp manufacturer_session_gln(user) do
    ThamaniDawa.Sites.get_site!(user.organization_id, user.current_site_id).gln
  end
end
