defmodule ThamaniDawaWeb.LabStockLiveTest do
  @moduledoc """
  Covers the acceptance criteria for the lab stock view: lab staff and admins
  see lab site batches, site/status filters narrow the list, and drill-downs
  show product batch roll-ups and batch usage history.
  """

  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures
  import ThamaniDawa.SuppliersFixtures

  describe "access control" do
    test "an admin can reach it", %{conn: conn} do
      admin = user_fixture()
      assert {:ok, _view, _html} = live(log_in_user(conn, admin), ~p"/lab/stock")
    end

    test "a lab technician can reach it", %{conn: conn} do
      lab_technician = staff_fixture(%{role: :lab_technician})
      assert {:ok, _view, _html} = live(log_in_user(conn, lab_technician), ~p"/lab/stock")
    end

    test "combined pharmacy/lab staff can reach it", %{conn: conn} do
      pharma_lab = staff_fixture(%{role: :pharma_lab})
      assert {:ok, _view, _html} = live(log_in_user(conn, pharma_lab), ~p"/lab/stock")
    end

    test "a pharmacist without lab access is redirected", %{conn: conn} do
      pharmacy_site = site_fixture(%{activities: [:pharmacy]})

      pharmacist =
        staff_fixture(%{
          role: :pharmacist,
          site_ids: [pharmacy_site.id],
          organization_id: pharmacy_site.organization_id
        })

      assert {:error, {:redirect, %{to: "/pharmacy"}}} =
               live(log_in_user(conn, pharmacist), ~p"/lab/stock")
    end

    test "an anonymous visitor is redirected away", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/lab/stock")
    end
  end

  describe "lab stock browsing and filtering" do
    setup do
      admin = user_fixture()
      org_id = admin.organization_id

      lab_site =
        site_fixture(%{organization_id: org_id, name: "Main Lab", activities: [:laboratory]})

      pharmacy_site =
        site_fixture(%{organization_id: org_id, name: "Pharma Only", activities: [:pharmacy]})

      product1 =
        product_fixture(%{organization_id: org_id, generic_name: "Reagent Alpha"})

      product2 =
        product_fixture(%{organization_id: org_id, generic_name: "Reagent Beta"})

      supplier = supplier_fixture(%{organization_id: org_id})

      batch_active =
        batch_fixture(%{
          organization_id: org_id,
          product_id: product1.id,
          site_id: lab_site.id,
          supplier_id: supplier.id,
          batch_no: "LAB-BATCH-001",
          approver_id: admin.id
        })

      batch_pending =
        batch_fixture(%{
          organization_id: org_id,
          product_id: product2.id,
          site_id: lab_site.id,
          supplier_id: supplier.id,
          batch_no: "LAB-BATCH-002",
          pending: true
        })

      pharmacy_batch =
        batch_fixture(%{
          organization_id: org_id,
          product_id: product1.id,
          site_id: pharmacy_site.id,
          supplier_id: supplier.id,
          batch_no: "PHARMA-BATCH-999",
          approver_id: admin.id
        })

      tech =
        staff_fixture(%{
          role: :lab_technician,
          site_ids: [lab_site.id],
          organization_id: org_id
        })

      %{
        admin: admin,
        tech: tech,
        lab_site: lab_site,
        pharmacy_site: pharmacy_site,
        product1: product1,
        product2: product2,
        batch_active: batch_active,
        batch_pending: batch_pending,
        pharmacy_batch: pharmacy_batch
      }
    end

    test "displays products view by default and lists product summary", %{conn: conn, tech: tech} do
      {:ok, view, html} = live(log_in_user(conn, tech), ~p"/lab/stock")

      assert html =~ "Lab stock"
      assert has_element?(view, "#lab-stock-toolbar")
      assert has_element?(view, ".td-tl #search-form")
      refute has_element?(view, "#lab-stock-toolbar #search-form")
      assert has_element?(view, "#lab-stock-chip-category", "Category")
      assert has_element?(view, "#lab-stock-chip-status", "Status")
      assert has_element?(view, "#lab-stock-chip-expiry", "Expiry")
      assert has_element?(view, "#products-tab.is-active")
      assert html =~ "Reagent Alpha"
      assert html =~ "Reagent Beta"
    end

    test "switching to batches view lists lab batches", %{conn: conn, tech: tech} do
      {:ok, view, _html} = live(log_in_user(conn, tech), ~p"/lab/stock")

      html =
        view
        |> element("#batches-tab")
        |> render_click()

      assert html =~ "LAB-BATCH-001"
      assert html =~ "LAB-BATCH-002"
    end

    test "search filters product list", %{conn: conn, tech: tech} do
      {:ok, view, _html} = live(log_in_user(conn, tech), ~p"/lab/stock")

      html =
        view
        |> form("#search-form", %{search: "Alpha"})
        |> render_change()

      assert html =~ "Reagent Alpha"
      refute html =~ "Reagent Beta"
    end

    test "status filter narrows batch list", %{conn: conn, tech: tech} do
      {:ok, view, _html} = live(log_in_user(conn, tech), ~p"/lab/stock")

      view |> element("#batches-tab") |> render_click()

      view |> element("#lab-stock-status-pending") |> render_click()

      html = render(view)
      assert html =~ "LAB-BATCH-002"
      refute html =~ "LAB-BATCH-001"
      assert has_element?(view, "#lab-stock-chip-status", "Pending receipt")
    end

    test "drilling down to product details lists product batches at lab sites", %{
      conn: conn,
      tech: tech,
      product1: product1
    } do
      {:ok, view, html} = live(log_in_user(conn, tech), ~p"/lab/stock/products/#{product1.id}")

      assert html =~ "Reagent Alpha"
      assert has_element?(view, "#stock-product-scan", "Scan lookup")
      assert has_element?(view, "#stock-product-requisition", "Add to requisition")
      assert html =~ "LAB-BATCH-001"
      refute html =~ "PHARMA-BATCH-999"
    end

    test "drilling down to batch details displays batch info and usage history", %{
      conn: conn,
      tech: tech,
      batch_active: batch_active
    } do
      {:ok, view, html} =
        live(log_in_user(conn, tech), ~p"/lab/stock/batches/#{batch_active.id}")

      assert html =~ "Batch LAB-BATCH-001"
      assert html =~ "Usage history"
      assert has_element?(view, ".td-back-link", "Back to product")

      view |> element("#print-data-matrix") |> render_click()
      assert has_element?(view, "#data-matrix-modal", "Print Data Matrix")
      assert has_element?(view, "#print-data-matrix-labels", "Print labels")
    end
  end

  describe "Products tab" do
    test "lists only stock held at lab sites, not undispatched warehouse stock", %{conn: conn} do
      admin = user_fixture()
      org_id = admin.organization_id
      lab_site = site_fixture(%{organization_id: org_id, activities: [:laboratory]})

      product =
        product_fixture(%{organization_id: org_id, generic_name: "Awaiting Dispatch Reagent"})

      batch_fixture(%{
        organization_id: org_id,
        site_id: lab_site.id,
        product_id: product.id,
        quantity: 7,
        remaining_quantity: 7
      })

      org_batch_fixture(%{organization_id: org_id, product_id: product.id, quantity: 40})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/lab/stock")

      assert has_element?(lv, "#products-#{product.id}", "Awaiting Dispatch Reagent")
      assert has_element?(lv, "#products-#{product.id} .td-remaining", "7")
      refute has_element?(lv, "#products-#{product.id} .td-remaining", "47")
    end

    test "the stat strip counts out-of-stock and low products and links to them", %{conn: conn} do
      admin = user_fixture()
      org_id = admin.organization_id
      lab_site = site_fixture(%{organization_id: org_id, activities: [:laboratory]})

      empty =
        product_fixture(%{
          organization_id: org_id,
          generic_name: "Empty Reagent",
          price: 100,
          reorder_level: 10
        })

      batch_fixture(%{
        organization_id: org_id,
        site_id: lab_site.id,
        product_id: empty.id,
        quantity: 10,
        remaining_quantity: 0
      })

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/lab/stock")

      assert has_element?(lv, "#lab-stock-stat-out", "1 out of stock")
      assert has_element?(lv, "#lab-stock-stat-reorder", "KSh 1,000 to reorder")

      lv |> element("#lab-stock-stat-out") |> render_click()
      assert_patch(lv, ~p"/lab/stock?status=out")
      assert has_element?(lv, "#products-#{empty.id}", "Out of stock")
    end

    test "Export CSV downloads the filtered rows", %{conn: conn} do
      admin = user_fixture()
      org_id = admin.organization_id
      lab_site = site_fixture(%{organization_id: org_id, activities: [:laboratory]})
      product = product_fixture(%{organization_id: org_id, generic_name: "Csv Reagent"})
      batch_fixture(%{organization_id: org_id, site_id: lab_site.id, product_id: product.id})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/lab/stock")

      lv |> element("#lab-stock-export") |> render_click()
      assert has_element?(lv, "#lab-stock-export-modal", "Export CSV")

      lv |> form("#lab-stock-export-modal-form", %{columns: "visible"}) |> render_submit()
      assert_push_event(lv, "td:csv", %{filename: "lab-stock-products-" <> _, content: content})
      assert content =~ "Product,GTIN,Category"
      assert content =~ "Csv Reagent"
      refute has_element?(lv, "#lab-stock-export-modal")
      assert has_element?(lv, "#lab-stock-download-ready", "Your file is ready")
      assert has_element?(lv, "#lab-stock-download-ready", "ready")
      lv |> element("#lab-stock-download-ready button", "Done") |> render_click()
      refute has_element?(lv, "#lab-stock-download-ready")
    end

    test "a product at or below reorder_level shows the Low stock badge", %{conn: conn} do
      admin = user_fixture()
      org_id = admin.organization_id
      lab_site = site_fixture(%{organization_id: org_id, activities: [:laboratory]})

      low_stock_product =
        product_fixture(%{
          organization_id: org_id,
          generic_name: "Low Stock Reagent",
          reorder_level: 10
        })

      batch_fixture(%{
        organization_id: org_id,
        site_id: lab_site.id,
        product_id: low_stock_product.id,
        quantity: 5,
        remaining_quantity: 5
      })

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/lab/stock")
      html = render_click(lv, "set_view", %{"view" => "products"})

      assert html =~ "Low Stock Reagent"
      assert html =~ "Low stock"
    end
  end
end
