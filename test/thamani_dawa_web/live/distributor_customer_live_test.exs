defmodule ThamaniDawaWeb.DistributorCustomerLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.DistributorFixtures

  alias ThamaniDawa.Customers

  setup %{conn: conn} do
    distributor = distributor_user_fixture(%{roles: [:admin, :distributor]})
    conn = conn |> init_test_session(%{}) |> ThamaniDawaWeb.UserAuth.log_in_user(distributor)
    %{conn: conn, distributor: distributor}
  end

  test "a new account shows the first-customer empty state", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/distributor/customers")
    assert has_element?(view, "#customers-empty", "No customers yet")
    assert has_element?(view, "#customers-empty-add")
  end

  test "lists customers with order stats and opens the side panel", %{
    conn: conn,
    distributor: distributor
  } do
    org_id = distributor.organization_id
    destination = destination_fixture(org_id)

    {:ok, customer} =
      Customers.create_customer(org_id, %{
        "name" => "Kisumu Medical Centre",
        "customer_type" => "hospital",
        "gln" => destination.gln,
        "address" => "Oginga Odinga St, Kisumu"
      })

    shipment =
      shipment_fixture(org_id, distributor, %{
        destination: destination,
        order_number: "PO-KMC-0412"
      })

    {:ok, view, _html} = live(conn, ~p"/distributor/customers")
    assert has_element?(view, "#distributor-customers", "Kisumu Medical Centre")
    refute has_element?(view, "#customer-panel")

    view |> element("#customers-#{customer.id}") |> render_click()
    assert_patch(view, ~p"/distributor/customers?customer=#{customer.id}")
    assert has_element?(view, "#customer-panel", "Kisumu Medical Centre")
    assert has_element?(view, "#customer-stats", "Open orders")
    assert has_element?(view, "#customer-order-#{shipment.id}", "PO-KMC-0412")

    {:ok, view, _html} = live(conn, ~p"/distributor/customers?search=nobody")
    assert has_element?(view, "#customers-empty", "Nothing matches")
  end

  test "editing a customer saves from the modal footer", %{conn: conn, distributor: distributor} do
    {:ok, customer} =
      Customers.create_customer(distributor.organization_id, %{
        "name" => "Coast Diagnostics",
        "customer_type" => "other"
      })

    {:ok, view, _html} = live(conn, ~p"/distributor/customers/#{customer.id}/edit")
    assert has_element?(view, "#distributor-customer-modal", "Edit customer")

    view
    |> form("#distributor-customer-form", customer: %{name: "Coast Diagnostics Ltd"})
    |> render_submit()

    assert_patch(view, ~p"/distributor/customers")
    assert has_element?(view, "#distributor-customers", "Coast Diagnostics Ltd")
  end

  test "adding a customer uses the shared GLN search, or no GLN at all", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/distributor/customers/new")
    assert has_element?(view, "#customer-gln")
    assert has_element?(view, "#save-customer[disabled]")

    view |> element("#customer-no-gln") |> render_click()
    refute has_element?(view, "#save-customer[disabled]")

    view
    |> form("#distributor-customer-form",
      customer: %{name: "Nakuru Town Pharmacy", customer_type: "pharmacy"}
    )
    |> render_submit()

    assert_patch(view, ~p"/distributor/customers")
    assert has_element?(view, "#distributor-customers", "Nakuru Town Pharmacy")
  end
end
