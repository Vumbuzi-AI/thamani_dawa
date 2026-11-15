defmodule ThamaniDawaWeb.DistributorRoutesTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.DistributorFixtures

  alias ThamaniDawa.ProductsFixtures
  alias ThamaniDawaWeb.UserAuth

  defp log_in(conn, user), do: conn |> init_test_session(%{}) |> UserAuth.log_in_user(user)

  setup %{conn: conn} do
    distributor = distributor_user_fixture(%{roles: [:admin, :distributor]})
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

      assert {:error, {:redirect, %{to: "/org/dashboard", flash: flash}}} =
               live(conn, ~p"/distributor")

      assert flash["error"] == "You don't have access to the distributor portal."
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

  describe "admin/distributor role separation" do
    setup %{conn: conn, distributor: admin} do
      staff =
        distributor_user_fixture(%{organization_id: admin.organization_id, roles: [:distributor]})

      prepay_allowance_fixture(admin.organization_id, admin, 100)

      %{conn: log_in(conn, staff), staff: staff}
    end

    test "non-admin staff can still reach day-to-day operations", %{conn: conn} do
      for path <- [~p"/distributor", ~p"/distributor/shipments", ~p"/distributor/products"] do
        assert {:ok, _view, _html} = live(conn, path)
      end
    end

    test "non-admin staff are bounced back to the portal from admin-only pages", %{conn: conn} do
      for path <- [
            ~p"/distributor/mobile-users",
            ~p"/distributor/settings",
            ~p"/distributor/epcis"
          ] do
        assert {:error, {:redirect, %{to: "/distributor"}}} = live(conn, path)
      end
    end
  end

  describe "portal basics" do
    test "products, receiving and settings render", %{
      conn: conn
    } do
      for {path, selector} <- [
            {~p"/distributor/products", "#distributor-products"},
            {~p"/distributor/receiving", "#distributor-receipts"},
            {~p"/distributor/settings", "#distributor-gs1-settings-form"}
          ] do
        assert {:ok, view, _html} = live(conn, path)
        assert has_element?(view, selector)

        if path == ~p"/distributor/receiving" do
          assert has_element?(view, ~s(a[href="/distributor/receiving"][aria-current="page"]))
        end
      end
    end

    test "opens the receive-stock form without a browser refresh", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/distributor/receiving")

      view |> element("#receive-distributor-stock") |> render_click()

      assert_patch(view, ~p"/distributor/receiving/new")
      assert has_element?(view, "#open-add-item-empty")
      refute has_element?(view, "#distributor-receipts")
    end

    test "product tabs and search share the responsive toolbar row", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/distributor/products")

      assert has_element?(
               view,
               "#distributor-product-toolbar #distributor-products-tab"
             )

      assert has_element?(
               view,
               "#distributor-product-toolbar #distributor-product-search"
             )
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

    test "prepay checkout confirms a manual reference immediately", %{
      conn: conn,
      distributor: distributor
    } do
      {:ok, view, _html} = live(conn, ~p"/distributor/billing/options")
      view |> element("#choose-prepay") |> render_click()

      {:ok, checkout, _html} = live(conn, ~p"/distributor/billing/payment")

      checkout
      |> form("#distributor-payment-form", payment: %{method: "manual"})
      |> render_change()

      refute has_element?(checkout, "input[value='mpesa']")

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
      destination = destination_fixture(organization_id)
      %{warehouse: warehouse, destination: destination}
    end

    test "creating a draft shipment", %{
      conn: conn,
      warehouse: warehouse,
      destination: destination
    } do
      {:ok, view, _html} = live(conn, ~p"/distributor/shipments/new")

      view
      |> form("#distributor-shipment-form",
        shipment: %{
          order_number: "PO-7781",
          origin_gln: warehouse.gln,
          destination_gln: destination.gln
        }
      )
      |> render_change(%{"_target" => ["shipment", "destination_gln"]})

      render_async(view, 5_000)

      assert {:error, {:live_redirect, %{to: "/distributor/shipments/" <> _id}}} =
               view
               |> form("#distributor-shipment-form",
                 shipment: %{
                   order_number: "PO-7781",
                   origin_gln: warehouse.gln,
                   destination_gln: destination.gln
                 }
               )
               |> render_submit()
    end

    test "approving a submitted shipment issues SSCC labels", %{
      conn: conn,
      distributor: distributor,
      warehouse: warehouse,
      destination: destination
    } do
      batch = received_unit_fixture(distributor.organization_id, warehouse.id, distributor.id)

      shipment =
        submitted_shipment_fixture(distributor.organization_id, distributor, [batch], %{
          warehouse: warehouse,
          destination: destination
        })

      usage = ThamaniDawa.Distributor.Billing.active_usage(distributor.organization_id)

      ThamaniDawa.Repo.update!(Ecto.Changeset.change(usage, running_quantity: 40))

      {:ok, index, _html} = live(conn, ~p"/distributor/shipments")
      assert has_element?(index, "#distributor-shipments")
      assert has_element?(index, "#filter-status")

      {:ok, view, _html} = live(conn, ~p"/distributor/shipments/#{shipment.id}")
      assert has_element?(view, "#approve-distributor-shipment")

      view |> element("#approve-distributor-shipment") |> render_click()
      assert has_element?(view, "#distributor-approve-modal")
      assert has_element?(view, "#approval-order-number", shipment.order_number)
      assert has_element?(view, "#approval-shipper-count", "1")
      assert has_element?(view, "#approval-sscc-count", "1")
      assert has_element?(view, "#approval-credit-count", "1")
      assert has_element?(view, "#approval-current-allowance", "60")
      assert has_element?(view, "#approval-remaining-allowance", "59")
      refute has_element?(view, "#distributor-sscc-labels")

      view |> element("#confirm-approve-shipment") |> render_click()
      render_async(view, 1_000)

      assert has_element?(view, "#distributor-sscc-labels")
      assert has_element?(view, "#distributor-sscc-labels .printable-sscc-label")
      refute has_element?(view, "#approve-distributor-shipment")
    end

    test "cancel closes the approval modal without approving", %{
      conn: conn,
      distributor: distributor,
      warehouse: warehouse,
      destination: destination
    } do
      batch = received_unit_fixture(distributor.organization_id, warehouse.id, distributor.id)

      shipment =
        submitted_shipment_fixture(distributor.organization_id, distributor, [batch], %{
          warehouse: warehouse,
          destination: destination
        })

      {:ok, view, _html} = live(conn, ~p"/distributor/shipments/#{shipment.id}")
      view |> element("#approve-distributor-shipment") |> render_click()
      view |> element("#cancel-approve-shipment") |> render_click()

      refute has_element?(view, "#distributor-approve-modal")
      assert has_element?(view, "#approve-distributor-shipment")
    end

    test "shows an insufficient allowance warning and ignores repeated confirmation", %{
      conn: conn,
      distributor: distributor,
      warehouse: warehouse,
      destination: destination
    } do
      usage = ThamaniDawa.Distributor.Billing.active_usage(distributor.organization_id)

      ThamaniDawa.Repo.update!(
        Ecto.Changeset.change(usage, running_quantity: usage.quantity_limit)
      )

      batch = received_unit_fixture(distributor.organization_id, warehouse.id, distributor.id)

      shipment =
        submitted_shipment_fixture(distributor.organization_id, distributor, [batch], %{
          warehouse: warehouse,
          destination: destination
        })

      {:ok, view, _html} = live(conn, ~p"/distributor/shipments/#{shipment.id}")
      view |> element("#approve-distributor-shipment") |> render_click()
      assert has_element?(view, "#approval-current-allowance", "0")
      assert has_element?(view, "#approval-insufficient-allowance", "only 0 remain")

      view |> element("#confirm-approve-shipment") |> render_click()
      render_click(view, "approve", %{})
      render_async(view, 1_000)
      assert has_element?(view, "#distributor-sscc-labels")
      updated_usage = ThamaniDawa.Distributor.Billing.active_usage(distributor.organization_id)

      assert updated_usage.running_quantity + updated_usage.running_buffer ==
               updated_usage.quantity_limit + 1
    end

    test "non-distributor users cannot access a shipment approval screen", %{
      distributor: distributor,
      warehouse: warehouse,
      destination: destination
    } do
      batch = received_unit_fixture(distributor.organization_id, warehouse.id, distributor.id)

      shipment =
        submitted_shipment_fixture(distributor.organization_id, distributor, [batch], %{
          warehouse: warehouse,
          destination: destination
        })

      unauthorized =
        staff_fixture(%{organization_id: distributor.organization_id, role: :pharmacist})

      assert {:error, {:redirect, %{to: "/pharmacy", flash: flash}}} =
               live(log_in(build_conn(), unauthorized), ~p"/distributor/shipments/#{shipment.id}")

      assert flash["error"] == "You don't have access to the distributor portal."
    end

    test "rejecting requires a reason", %{
      conn: conn,
      distributor: distributor,
      warehouse: warehouse,
      destination: destination
    } do
      batch = received_unit_fixture(distributor.organization_id, warehouse.id, distributor.id)

      shipment =
        submitted_shipment_fixture(distributor.organization_id, distributor, [batch], %{
          warehouse: warehouse,
          destination: destination
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
      destination: destination
    } do
      batch = received_unit_fixture(distributor.organization_id, warehouse.id, distributor.id)

      shipment =
        submitted_shipment_fixture(distributor.organization_id, distributor, [batch], %{
          warehouse: warehouse,
          destination: destination
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

    test "mobile user rows keep all actions in a non-shrinking action area", %{
      conn: conn,
      distributor: distributor
    } do
      mobile_user = mobile_user_fixture(distributor.organization_id)
      {:ok, view, _html} = live(conn, ~p"/distributor/mobile-users")

      actions = "#mobile-user-actions-#{mobile_user.id}"

      assert has_element?(view, "#distributor-mobile-users tr")
      assert has_element?(view, "#{actions}.sm\\:min-w-\\[19rem\\]")
      assert has_element?(view, "#{actions} > #edit-mobile-user-#{mobile_user.id}.shrink-0")
      assert has_element?(view, "#{actions} > #resend-pin-#{mobile_user.id}.shrink-0")
      assert has_element?(view, "#{actions} > #toggle-mobile-user-#{mobile_user.id}.shrink-0")
    end
  end

  describe "receiving" do
    test "a valid GTIN selects its catalog product", %{conn: conn, distributor: distributor} do
      product = ProductsFixtures.product_fixture(%{organization_id: distributor.organization_id})

      assert {:ok, view, _html} = live(conn, ~p"/distributor/receiving/new")

      view |> element("#open-add-item-empty") |> render_click()

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
