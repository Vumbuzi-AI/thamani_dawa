defmodule ThamaniDawaWeb.DistributorRoutesTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.DistributorFixtures

  alias ThamaniDawa.ProductsFixtures
  alias ThamaniDawaWeb.UserAuth

  defp log_in(conn, user), do: conn |> init_test_session(%{}) |> UserAuth.log_in_user(user)

  setup %{conn: conn} do
    distributor = distributor_user_fixture()
    %{conn: log_in(conn, distributor), distributor: distributor}
  end

  describe "access" do
    test "a distributor in a distributor organization can open the portal", %{conn: conn} do
      assert {:ok, view, _html} = live(conn, ~p"/distributor")
      assert has_element?(view, "#sidebar-shell")
      assert has_element?(view, "#stat-shipments-submitted")
      assert has_element?(view, "#distributor-plan-required")
    end

    test "an admin is redirected away" do
      conn = log_in(build_conn(), user_fixture())
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/distributor")
    end

    test "a distributor-role user outside a distributor organization is redirected away" do
      pharmacy_org =
        ThamaniDawa.OrganizationsFixtures.organization_fixture(%{operating_models: [:pharmacy]})

      user = staff_fixture(%{organization_id: pharmacy_org.id, role: :distributor})

      assert {:error, {:redirect, %{to: "/"}}} =
               live(log_in(build_conn(), user), ~p"/distributor")
    end

    test "an anonymous visitor is redirected away" do
      assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), ~p"/distributor")
    end
  end

  describe "portal basics" do
    test "customers, warehouses, products, suppliers, receiving and settings render", %{
      conn: conn
    } do
      for {path, selector} <- [
            {~p"/distributor/customers", "#distributor-customers"},
            {~p"/distributor/warehouses", "#distributor-warehouses"},
            {~p"/distributor/products", "#distributor-products"},
            {~p"/distributor/suppliers", "#distributor-suppliers"},
            {~p"/distributor/receiving", "#distributor-receipts"},
            {~p"/distributor/settings", "#distributor-gs1-settings-form"}
          ] do
        assert {:ok, view, _html} = live(conn, path)
        assert has_element?(view, selector)
      end
    end

    test "a new customer gets a GLN", %{conn: conn, distributor: distributor} do
      {:ok, view, _html} = live(conn, ~p"/distributor/customers/new")

      view
      |> form("#distributor-customer-form", customer: %{name: "Kisumu Clinic"})
      |> render_submit()

      [customer] = ThamaniDawa.DistributorCustomers.list_customers(distributor.organization_id)
      assert customer.gln =~ ~r/^\d{13}$/
    end
  end

  describe "serialisation plan gate" do
    test "shipment screens send you to the plan chooser until a plan is picked", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/distributor/billing/options"}}} =
               live(conn, ~p"/distributor/shipments")

      assert {:error, {:redirect, %{to: "/distributor/billing/options"}}} =
               live(conn, ~p"/distributor/mobile-users")
    end

    test "choosing flex opens a cycle and unlocks shipments", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/distributor/billing/options")

      assert {:error, {:live_redirect, %{to: "/distributor/shipments"}}} =
               view |> element("#choose-flex") |> render_click()

      assert {:ok, _view, _html} = live(conn, ~p"/distributor/shipments")
      assert {:ok, billing, _html} = live(conn, ~p"/distributor/billing")
      assert has_element?(billing, "#distributor-flex-usage")
    end

    test "prepay checkout with a manual reference credits the bundle", %{
      conn: conn,
      distributor: distributor
    } do
      {:ok, view, _html} = live(conn, ~p"/distributor/billing/options")
      view |> element("#choose-prepay") |> render_click()

      {:ok, checkout, _html} = live(conn, ~p"/distributor/billing/payment")

      checkout
      |> form("#distributor-payment-form", payment: %{method: "manual"})
      |> render_change()

      assert {:error, {:live_redirect, %{to: "/distributor/billing"}}} =
               checkout
               |> form("#distributor-payment-form",
                 payment: %{quantity: "500", method: "manual", manual_reference: "BANK-42"}
               )
               |> render_submit()

      usage = ThamaniDawa.Distributor.Billing.active_usage(distributor.organization_id)
      assert usage.quantity_limit == 500
    end
  end

  describe "shipments" do
    setup %{distributor: distributor} do
      organization_id = distributor.organization_id
      prepay_allowance_fixture(organization_id, distributor, 100)
      warehouse = warehouse_fixture(organization_id)
      customer = customer_fixture(organization_id)
      %{warehouse: warehouse, customer: customer}
    end

    test "creating a draft shipment", %{conn: conn, warehouse: warehouse, customer: customer} do
      {:ok, view, _html} = live(conn, ~p"/distributor/shipments/new")

      assert {:error, {:live_redirect, %{to: "/distributor/shipments/" <> _id}}} =
               view
               |> form("#distributor-shipment-form",
                 shipment: %{
                   order_number: "PO-7781",
                   origin_gln: warehouse.gln,
                   destination_gln: customer.gln
                 }
               )
               |> render_submit()
    end

    test "approving a submitted shipment issues SSCC labels", %{
      conn: conn,
      distributor: distributor,
      warehouse: warehouse,
      customer: customer
    } do
      batch = received_unit_fixture(distributor.organization_id, warehouse.id, distributor.id)

      shipment =
        submitted_shipment_fixture(distributor.organization_id, distributor, [batch], %{
          warehouse: warehouse,
          customer: customer
        })

      {:ok, index, _html} = live(conn, ~p"/distributor/shipments")
      assert has_element?(index, "#distributor-shipments")
      assert has_element?(index, "#shipment-tab-submitted")

      {:ok, view, _html} = live(conn, ~p"/distributor/shipments/#{shipment.id}")
      assert has_element?(view, "#approve-distributor-shipment")

      view |> element("#approve-distributor-shipment") |> render_click()

      assert has_element?(view, "#distributor-sscc-labels")
      refute has_element?(view, "#approve-distributor-shipment")
    end

    test "rejecting requires a reason", %{
      conn: conn,
      distributor: distributor,
      warehouse: warehouse,
      customer: customer
    } do
      batch = received_unit_fixture(distributor.organization_id, warehouse.id, distributor.id)

      shipment =
        submitted_shipment_fixture(distributor.organization_id, distributor, [batch], %{
          warehouse: warehouse,
          customer: customer
        })

      {:ok, view, _html} = live(conn, ~p"/distributor/shipments/#{shipment.id}")
      view |> element("#reject-distributor-shipment") |> render_click()

      view
      |> form("#distributor-reject-form", reject: %{reason: "Shipper 1 holds expired stock"})
      |> render_submit()

      assert has_element?(view, "#distributor-rejection-reason")
    end

    test "CSV export lists scanned units", %{
      conn: conn,
      distributor: distributor,
      warehouse: warehouse,
      customer: customer
    } do
      batch = received_unit_fixture(distributor.organization_id, warehouse.id, distributor.id)

      shipment =
        submitted_shipment_fixture(distributor.organization_id, distributor, [batch], %{
          warehouse: warehouse,
          customer: customer
        })

      conn = get(conn, ~p"/distributor/shipments/#{shipment.id}/export")
      assert response_content_type(conn, :csv)
      assert response(conn, 200) =~ batch.serial
    end

    test "adding a mobile user emails their PIN", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/distributor/mobile-users/new")

      view
      |> form("#distributor-mobile-user-form",
        mobile_user: %{name: "Jane Packer", username: "jane.packer", email: "jane@example.com"}
      )
      |> render_submit()

      assert has_element?(view, "#distributor-mobile-users", "Jane Packer")
      assert_received {:email, %Swoosh.Email{subject: "Your Thamani Dawa mobile app PIN"}}
    end
  end

  describe "receiving" do
    test "a valid GTIN selects its catalog product", %{conn: conn, distributor: distributor} do
      product = ProductsFixtures.product_fixture(%{organization_id: distributor.organization_id})

      assert {:ok, view, _html} = live(conn, ~p"/distributor/receiving/new")

      view
      |> form("#distributor-scan-gtin-form", scan: %{gtin: product.gtin <> " "})
      |> render_change()

      assert has_element?(
               view,
               "#distributor-receipt-form input[name='batch[gtin]'][value='#{product.gtin}']"
             )
    end
  end
end
