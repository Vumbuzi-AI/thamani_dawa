defmodule ThamaniDawaWeb.QuickSaleLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures

  defp pharmacist_at_site(organization, site) do
    staff_fixture(%{organization_id: organization.id, site_id: site.id})
  end

  describe "Quick sale page" do
    test "Quick sale appears in the pharmacy sidebar nav", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy")

      assert has_element?(lv, "a[href='/pharmacy/quick-sale']", "Quick sale")
    end

    test "prompts an org-wide admin to choose a site before showing stock-is-empty copy", %{
      conn: conn
    } do
      organization = organization_fixture()
      site_a = site_fixture(%{organization_id: organization.id})
      site_fixture(%{organization_id: organization.id})
      admin = user_fixture(%{organization_id: organization.id})

      product = product_fixture(%{organization_id: organization.id})

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site_a.id,
        product_id: product.id,
        quantity: 20
      })

      {:ok, lv, html} = live(log_in_user(conn, admin), ~p"/pharmacy/quick-sale")

      assert has_element?(lv, "select[name='site_id']")
      assert html =~ "Choose a site to get started"
      refute html =~ "No active stock is available at this site."
    end

    test "does not offer patient selection", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/quick-sale")

      refute has_element?(lv, "select[name='patient_id']")
      refute has_element?(lv, "button", "+ Link to a patient (optional)")
    end

    test "shows the quick-add grid and hides the site picker for a single-site staff member", %{
      conn: conn
    } do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)
      product = product_fixture(%{organization_id: organization.id, generic_name: "Amoxicillin"})

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        quantity: 20
      })

      {:ok, lv, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/quick-sale")

      assert html =~ "Amoxicillin"
      refute has_element?(lv, "select[name='site_id']")
      assert has_element?(lv, "#quick-add-#{product.id}")
      assert has_element?(lv, "#quick-sale-cart-header", "Current sale")
      assert has_element?(lv, "#quick-sale-item-count", "0 items")
      assert has_element?(lv, "#quick-sale-catalog-header", "Product catalog")
    end

    test "clicking a quick-add tile adds it to the cart", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)
      product = product_fixture(%{organization_id: organization.id, price: 50})

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        quantity: 20
      })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/quick-sale")

      html = lv |> element("#quick-add-#{product.id}") |> render_click()

      assert has_element?(lv, "#cart-line-#{product.id}")
      assert has_element?(lv, "#cart-verification-#{product.id}", "Scan to verify")
      assert has_element?(lv, "#quick-sale-item-count", "1 item")
      assert html =~ "KES 50"
    end

    test "scanning a matching barcode adds the product to the cart", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)
      product = product_fixture(%{organization_id: organization.id})

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        quantity: 20
      })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/quick-sale")

      render_submit(lv, "scan_submit", %{"query" => product.gtin})

      assert has_element?(lv, "#cart-line-#{product.id}")
      assert has_element?(lv, "#cart-verification-#{product.id}", "Verified")
      assert has_element?(lv, "#quick-sale-verification-summary", "All medicines verified")
    end

    test "scanning a catalog-added medicine verifies it without changing its quantity", %{
      conn: conn
    } do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)
      product = product_fixture(%{organization_id: organization.id})

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        quantity: 20
      })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/quick-sale")

      lv |> element("#quick-add-#{product.id}") |> render_click()
      render_submit(lv, "scan_submit", %{"query" => product.gtin})

      assert has_element?(lv, "#cart-quantity-#{product.id}[value='1']")
      assert has_element?(lv, "#cart-verification-#{product.id}", "Verified")
    end

    test "does not open payment until every medicine has been scanned", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)
      product = product_fixture(%{organization_id: organization.id})

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        quantity: 20
      })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/quick-sale")

      lv |> element("#quick-add-#{product.id}") |> render_click()
      render_click(lv, "select_payment_type", %{"payment_type" => "Cash"})
      html = render_click(lv, "complete_sale", %{})

      assert html =~ "Scan each medicine in the cart before taking payment."
      refute has_element?(lv, "#quick-sale-payment-modal")
    end

    test "scanning an unknown barcode shows a flash error and adds nothing", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)
      product = product_fixture(%{organization_id: organization.id})

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        quantity: 20
      })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/quick-sale")

      html = render_submit(lv, "scan_submit", %{"query" => unique_gtin()})

      assert html =~ "No product found for that barcode."
      refute has_element?(lv, "#cart-line-#{product.id}")
    end

    test "the quantity controls increment, accept a typed quantity, decrement, and remove at zero",
         %{
           conn: conn
         } do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)
      product = product_fixture(%{organization_id: organization.id})

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        quantity: 20
      })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/quick-sale")

      lv |> element("#quick-add-#{product.id}") |> render_click()
      assert has_element?(lv, "#cart-line-#{product.id}", "1")

      render_click(lv, "increment_item", %{"product_id" => to_string(product.id)})
      assert has_element?(lv, "#cart-line-#{product.id}", "2")

      lv
      |> element("#cart-quantity-form-#{product.id}")
      |> render_change(%{"product_id" => to_string(product.id), "quantity" => "12"})

      assert has_element?(lv, "#cart-quantity-#{product.id}[value='12']")

      render_click(lv, "decrement_item", %{"product_id" => to_string(product.id)})
      assert has_element?(lv, "#cart-quantity-#{product.id}[value='11']")

      render_change(lv, "set_item_quantity", %{
        "product_id" => to_string(product.id),
        "quantity" => "0"
      })

      refute has_element?(lv, "#cart-line-#{product.id}")
    end

    test "payment confirmation completes a sale and shows its complete receipt", %{
      conn: conn
    } do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id, name: "Medpoint CBD"})
      pharmacist = pharmacist_at_site(organization, site)

      product =
        product_fixture(%{
          organization_id: organization.id,
          generic_name: "Amoxicillin 500mg Cap",
          brand_name: "Amoxil",
          price: 50
        })

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        quantity: 20
      })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/quick-sale")

      lv |> element("#quick-add-#{product.id}") |> render_click()
      render_click(lv, "increment_item", %{"product_id" => to_string(product.id)})
      render_submit(lv, "scan_submit", %{"query" => product.gtin})

      render_click(lv, "select_payment_type", %{"payment_type" => "Cash"})

      render_click(lv, "complete_sale", %{})
      assert has_element?(lv, "#quick-sale-payment-modal")

      lv
      |> form("#quick-sale-payment-form", payment: %{tendered: "150"})
      |> render_submit()

      assert has_element?(lv, "#quick-sale-receipt-modal", "Sale complete")
      assert has_element?(lv, "#quick-sale-receipt", "Medpoint CBD")
      assert has_element?(lv, "#quick-sale-receipt", "Sale Receipt")
      assert has_element?(lv, "#quick-sale-receipt", "Receipt no.")
      assert has_element?(lv, "#receipt-date-time", "Date")
      assert has_element?(lv, "#quick-sale-receipt", pharmacist.name)
      assert has_element?(lv, "#quick-sale-receipt", "Qty")
      assert has_element?(lv, "#quick-sale-receipt", "Medicine")
      assert has_element?(lv, "#quick-sale-receipt", "Unit price")
      assert has_element?(lv, "#quick-sale-receipt", "Line total")
      assert has_element?(lv, "#quick-sale-receipt", "Amoxicillin 500mg Cap")
      assert has_element?(lv, "#receipt-total", "KES 100")
      assert has_element?(lv, "#receipt-cash-tendered", "KES 150")
      assert has_element?(lv, "#receipt-change", "KES 50")
      assert has_element?(lv, "#quick-sale-receipt", "Thank you for choosing Medpoint CBD.")
      assert has_element?(lv, "#quick-sale-receipt", "Powered by Thamani Dawa")

      assert has_element?(
               lv,
               "#quick-sale-print[phx-hook='QuickSaleReceiptPrint'][data-receipt-target='#quick-sale-receipt']"
             )

      assert ThamaniDawa.Batches.total_available_stock(organization.id, site.id, product.id) == 18

      lv |> element("#quick-sale-receipt-modal button", "New sale") |> render_click()
      refute has_element?(lv, "#quick-sale-receipt-modal")
      assert has_element?(lv, "#quick-sale-item-count", "0 items")

      assert has_element?(
               lv,
               "#quick-sale-cart",
               "Scan a barcode or tap a product to start the sale."
             )
    end

    test "M-Pesa receipt displays the transaction reference", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)
      product = product_fixture(%{organization_id: organization.id, price: 50})

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        quantity: 20
      })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/quick-sale")

      lv |> element("#quick-add-#{product.id}") |> render_click()
      render_submit(lv, "scan_submit", %{"query" => product.gtin})
      render_click(lv, "select_payment_type", %{"payment_type" => "Mobile Money"})
      render_click(lv, "complete_sale", %{})

      lv
      |> form("#quick-sale-payment-form", payment: %{provider_reference: "SFA7B2XQ9K"})
      |> render_submit()

      assert has_element?(lv, "#quick-sale-receipt-modal", "Sale complete")
      assert has_element?(lv, "#receipt-payment-method", "Mobile Money")
      assert has_element?(lv, "#receipt-mpesa-reference", "M-Pesa reference")
      assert has_element?(lv, "#receipt-mpesa-reference", "SFA7B2XQ9K")
    end

    test "completing a sale without a payment method shows an inline error and changes nothing",
         %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)
      product = product_fixture(%{organization_id: organization.id})

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        quantity: 20
      })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/quick-sale")

      lv |> element("#quick-add-#{product.id}") |> render_click()
      render_submit(lv, "scan_submit", %{"query" => product.gtin})
      html = render_click(lv, "complete_sale", %{})

      assert html =~ "Select a payment method."
      assert ThamaniDawa.Prescriptions.list_prescriptions(organization.id) == []
      assert ThamaniDawa.Batches.total_available_stock(organization.id, site.id, product.id) == 20
    end

    test "completing a sale with an empty cart shows a flash error", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/quick-sale")

      html = render_click(lv, "complete_sale", %{})

      assert html =~ "Add at least one item."
    end
  end
end
