defmodule ThamaniDawaWeb.DistributorCustomerReturnLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.DistributorFixtures
  import ThamaniDawa.ProductsFixtures

  alias ThamaniDawa.CustomerReturns
  alias ThamaniDawa.Customers
  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Distributor.ShipmentItem
  alias ThamaniDawa.Distributor.Shipper
  alias ThamaniDawa.Repo

  test "a return starts from the shipment and confirms a pack that came back", %{conn: conn} do
    org = distributor_organization_fixture()
    warehouse = warehouse_fixture(org.id)
    user = distributor_user_fixture(%{organization_id: org.id, site_id: warehouse.id})
    product = product_fixture(%{organization_id: org.id})
    destination = destination_fixture()

    {:ok, shipment} =
      Distributor.create_shipment(org.id, user, %{
        "order_number" => "PO-RETURN-1",
        "origin_gln" => warehouse.gln,
        "destination_gln" => destination.gln
      })

    shipment =
      shipment
      |> Ecto.Changeset.change(%{status: "approved"})
      |> Repo.update!()

    shipper =
      %Shipper{}
      |> Ecto.Changeset.change(%{
        organization_id: org.id,
        shipment_id: shipment.id,
        sequence: 1,
        name: "Shipper 1"
      })
      |> Repo.insert!()

    item =
      %ShipmentItem{}
      |> Ecto.Changeset.change(%{
        organization_id: org.id,
        shipment_id: shipment.id,
        shipper_id: shipper.id,
        raw_data_matrix: "raw",
        gtin: product.gtin,
        batch: "LOT-RET",
        serial: "SN-RET-1",
        expiry_date: Date.add(Date.utc_today(), 400),
        product_id: product.id,
        product_name: product.generic_name,
        product_source: "catalogue",
        validation_status: "ok",
        scanned_at: DateTime.utc_now(:second)
      })
      |> Repo.insert!()

    conn = log_in_user(conn, user)
    {:ok, view, html} = live(conn, ~p"/distributor/customer-returns/new")

    refute has_element?(view, "#customer-return-site")
    refute html =~ "Choose a warehouse"

    view
    |> form("#shipment-search-form", %{query: "PO-RETURN-1"})
    |> render_change()

    view |> element("#shipment-match-#{shipment.id}") |> render_click()

    assert has_element?(view, "#selected-shipment", "PO-RETURN-1")

    attach_return_documents(view)

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> form("#customer-return-form", %{
               customer_return: %{reason: "damaged"}
             })
             |> render_submit()

    {:ok, list, _html} = live(conn, ~p"/distributor/customer-returns")
    assert has_element?(list, "#customer-returns", "PO-RETURN-1")
    assert has_element?(list, "#cr-tab-all")

    {:ok, view, _html} = live(conn, to)

    assert has_element?(view, "#customer-return-detail")

    assert has_element?(
             view,
             "#customer-return-back[href='/distributor/customer-returns']",
             "Back to Customer returns"
           )

    assert has_element?(view, "#customer-return-summary", "PO-RETURN-1")
    refute has_element?(view, "#customer-returns")
    assert has_element?(view, "#return-pack-#{item.id}")
    refute has_element?(view, "#add-return-item-form")

    [customer_return] = CustomerReturns.list_returns(org.id)

    render_click(view, "add_item", %{
      "customer_return_id" => to_string(customer_return.id),
      "product_id" => to_string(product.id),
      "quantity" => "1",
      "batch_no" => "LOT-OFF-MANIFEST",
      "expiry_date" => Date.to_iso8601(Date.add(Date.utc_today(), 100))
    })

    assert CustomerReturns.get_return!(org.id, customer_return.id).items == []

    view |> element("#return-pack-#{item.id}") |> render_click()

    html = render(view)
    assert html =~ "SN-RET-1"
    refute has_element?(view, "#return-pack-#{item.id}")

    [customer_return] = CustomerReturns.list_returns(org.id)
    assert customer_return.shipment_id == shipment.id
    assert hd(customer_return.attachments).filename == "return-note.pdf"
    assert hd(customer_return.items).matched
    assert hd(customer_return.items).serial == "SN-RET-1"
  end

  test "all packs came back adds every pending pack in one click", %{conn: conn} do
    org = distributor_organization_fixture()
    warehouse = warehouse_fixture(org.id)
    user = distributor_user_fixture(%{organization_id: org.id, site_id: warehouse.id})
    product = product_fixture(%{organization_id: org.id})
    destination = destination_fixture()

    {:ok, shipment} =
      Distributor.create_shipment(org.id, user, %{
        "order_number" => "PO-RETURN-2",
        "origin_gln" => warehouse.gln,
        "destination_gln" => destination.gln
      })

    shipment =
      shipment
      |> Ecto.Changeset.change(%{status: "approved"})
      |> Repo.update!()

    shipper =
      %Shipper{}
      |> Ecto.Changeset.change(%{
        organization_id: org.id,
        shipment_id: shipment.id,
        sequence: 1,
        name: "Shipper 1"
      })
      |> Repo.insert!()

    [item1, item2] =
      for n <- 1..2 do
        %ShipmentItem{}
        |> Ecto.Changeset.change(%{
          organization_id: org.id,
          shipment_id: shipment.id,
          shipper_id: shipper.id,
          raw_data_matrix: "raw-#{n}",
          gtin: product.gtin,
          batch: "LOT-RET-#{n}",
          serial: "SN-RET-#{n}",
          expiry_date: Date.add(Date.utc_today(), 400),
          product_id: product.id,
          product_name: product.generic_name,
          product_source: "catalogue",
          validation_status: "ok",
          scanned_at: DateTime.utc_now(:second)
        })
        |> Repo.insert!()
      end

    conn = log_in_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/distributor/customer-returns/new")

    view
    |> form("#shipment-search-form", %{query: "PO-RETURN-2"})
    |> render_change()

    view |> element("#shipment-match-#{shipment.id}") |> render_click()

    attach_return_documents(view)

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> form("#customer-return-form", %{customer_return: %{reason: "damaged"}})
             |> render_submit()

    {:ok, view, _html} = live(conn, to)

    assert has_element?(view, "#add-all-shipment-items")
    assert has_element?(view, "#return-pack-#{item1.id}")
    assert has_element?(view, "#return-pack-#{item2.id}")

    html =
      view
      |> element("#add-all-shipment-items")
      |> render_click()

    assert html =~ "Added 2 pack(s) to the return."
    refute has_element?(view, "#return-pack-#{item1.id}")
    refute has_element?(view, "#return-pack-#{item2.id}")
    refute has_element?(view, "#add-all-shipment-items")

    [customer_return] = CustomerReturns.list_returns(org.id)
    assert length(customer_return.items) == 2
    assert Enum.all?(customer_return.items, & &1.matched)
  end

  test "mark inspected is blocked until every item has a condition", %{conn: conn} do
    org = distributor_organization_fixture()
    warehouse = warehouse_fixture(org.id)
    user = distributor_user_fixture(%{organization_id: org.id, site_id: warehouse.id})
    product = product_fixture(%{organization_id: org.id})

    {:ok, customer} =
      Customers.create_customer(org.id, %{
        "name" => "Kisumu Pharmacy",
        "customer_type" => "pharmacy"
      })

    {:ok, customer_return} =
      CustomerReturns.create_return(org.id, %{
        "customer_id" => customer.id,
        "site_id" => warehouse.id,
        "reason" => "damaged"
      })

    {:ok, item1} =
      CustomerReturns.add_item(customer_return, %{
        "product_id" => product.id,
        "quantity" => 1,
        "batch_no" => "LOT-A",
        "expiry_date" => Date.to_iso8601(Date.add(Date.utc_today(), 100))
      })

    {:ok, _item2} =
      CustomerReturns.add_item(customer_return, %{
        "product_id" => product.id,
        "quantity" => 1,
        "batch_no" => "LOT-B",
        "expiry_date" => Date.to_iso8601(Date.add(Date.utc_today(), 100))
      })

    {:ok, _received} = CustomerReturns.mark_received(customer_return, user.id)

    conn = log_in_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/distributor/customer-returns/#{customer_return.id}")

    assert has_element?(view, "#mark-inspected-needs-conditions")
    assert has_element?(view, "button[disabled]", "Mark inspected")
    assert has_element?(view, "#condition-form-#{item1.id}")

    # Simulates the real browser payload for this select: the JS client reads
    # phx-value-* off the *form* ancestor (extractMeta(inputEl.form)) and
    # merges it into "meta", which the server merges into params alongside
    # the select's own "condition" value — same as production, see the
    # matching fix in distributor_receiving_live.ex's quantity inputs.
    render_change(view, "set_condition", %{
      "item_id" => to_string(item1.id),
      "customer_return_id" => to_string(customer_return.id),
      "condition" => "sellable"
    })

    assert has_element?(view, "#mark-inspected-needs-conditions")

    [customer_return] = CustomerReturns.list_returns(org.id)

    {:ok, _item2} =
      customer_return.items
      |> Enum.find(&(&1.batch_no == "LOT-B"))
      |> CustomerReturns.set_item_condition("damaged")

    {:ok, view, _html} = live(conn, ~p"/distributor/customer-returns/#{customer_return.id}")
    refute has_element?(view, "#mark-inspected-needs-conditions")
    refute has_element?(view, "button[disabled]", "Mark inspected")

    view |> element("button", "Mark inspected") |> render_click()

    [customer_return] = CustomerReturns.list_returns(org.id)
    assert customer_return.status == :inspected
  end

  test "a return with no shipment records the customer and the document", %{conn: conn} do
    org = distributor_organization_fixture()
    warehouse = warehouse_fixture(org.id)
    user = distributor_user_fixture(%{organization_id: org.id, site_id: warehouse.id})

    {:ok, customer} =
      Customers.create_customer(org.id, %{
        "name" => "Kisumu Pharmacy",
        "customer_type" => "pharmacy"
      })

    conn = log_in_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/distributor/customer-returns/new")

    refute has_element?(view, "#return-customer-name")

    view |> element("#return-source-customer") |> render_click()

    assert has_element?(view, "#return-customer-name")
    refute has_element?(view, "select[name='customer_return[customer_id]']")

    attach_return_documents(view)

    view
    |> form("#customer-return-form", %{
      customer_name: "Kisumu Pharmacy",
      customer_return: %{reason: "overstock"}
    })
    |> render_submit()

    [customer_return] = CustomerReturns.list_returns(org.id)
    assert customer_return.customer_id == customer.id
    assert is_nil(customer_return.shipment_id)
    assert hd(customer_return.attachments).filename == "return-note.pdf"
  end

  test "a new customer name is saved with the return", %{conn: conn} do
    org = distributor_organization_fixture()
    warehouse = warehouse_fixture(org.id)
    user = distributor_user_fixture(%{organization_id: org.id, site_id: warehouse.id})

    conn = log_in_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/distributor/customer-returns/new")

    view |> element("#return-source-customer") |> render_click()

    attach_return_documents(view)

    view
    |> form("#customer-return-form", %{
      customer_name: "Walk-in Pharmacy",
      customer_return: %{reason: "damaged"}
    })
    |> render_submit()

    [customer_return] = CustomerReturns.list_returns(org.id)
    customer = Customers.get_customer!(org.id, customer_return.customer_id)
    assert customer.name == "Walk-in Pharmacy"
    assert customer.customer_type == :other
    assert is_nil(customer_return.shipment_id)
  end

  test "a return with no shipment needs the paperwork", %{conn: conn} do
    org = distributor_organization_fixture()
    warehouse = warehouse_fixture(org.id)
    user = distributor_user_fixture(%{organization_id: org.id, site_id: warehouse.id})

    conn = log_in_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/distributor/customer-returns/new")

    view |> element("#return-source-customer") |> render_click()

    html =
      view
      |> form("#customer-return-form", %{
        customer_name: "Walk-in Pharmacy",
        customer_return: %{reason: "damaged"}
      })
      |> render_submit()

    assert html =~ "Attach the related documents."
    assert CustomerReturns.list_returns(org.id) == []
  end

  defp attach_return_documents(view) do
    upload =
      file_input(view, "#customer-return-form", :return_documents, [
        %{
          name: "return-note.pdf",
          content: "return note",
          type: "application/pdf"
        }
      ])

    render_upload(upload, "return-note.pdf")
  end
end
