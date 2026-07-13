defmodule ThamaniDawaWeb.ProductLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures
  import ThamaniDawa.BatchesFixtures

  setup do
    admin = user_fixture()
    site = site_fixture(%{organization_id: admin.organization_id})
    {:ok, admin: admin, site: site}
  end

  describe "index" do
    test "lists products for the organization", %{conn: conn, admin: admin, site: site} do
      _product =
        product_fixture(%{
          organization_id: admin.organization_id,
          site_id: site.id,
          generic_name: "Test Aspirin"
        })

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/products")

      assert html =~ "Test Aspirin"
    end

    test "renders sidebar with correct hook for persistence", %{conn: conn, admin: admin} do
      {:ok, lv, html} = live(log_in_user(conn, admin), ~p"/org/products")

      # The hook and ID must be present for localstorage persistence to work
      assert has_element?(lv, "#sidebar-shell")
      assert has_element?(lv, "#sidebar-toggle")
      assert has_element?(lv, "#sidebar-aside")

      assert html =~ "Sidebar"
    end

    test "creates a new product", %{conn: conn, admin: admin, site: site} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")

      # Click Add product
      lv |> element("a", "+ Add product") |> render_click()

      # Submit the form
      lv
      |> form("form[phx-submit='save']",
        product: %{
          site_id: site.id,
          generic_name: "New Panadol",
          brand_name: "Panadol",
          category: "Painkiller",
          uom: "Pack",
          price: "50"
        }
      )
      |> render_submit()

      html = render(lv)
      assert html =~ "Product created."
      assert html =~ "New Panadol"
    end

    test "edits an existing product without duplicating it in the stream", %{
      conn: conn,
      admin: admin,
      site: site
    } do
      product =
        product_fixture(%{
          organization_id: admin.organization_id,
          site_id: site.id,
          generic_name: "Old Name"
        })

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")

      # Click Edit
      lv |> element("#products-#{product.id} a", "Edit") |> render_click()

      # Submit the form with new name
      lv
      |> form("form[phx-submit='save']",
        product: %{
          site_id: site.id,
          price: "100",
          generic_name: "Updated Name"
        }
      )
      |> render_submit()

      html = render(lv)
      assert html =~ "Product updated."
      assert html =~ "Updated Name"
      refute html =~ "Old Name"

      # Assert the product is only in the stream once (not duplicated)
      assert html |> String.split("id=\"products-#{product.id}\"") |> length() == 2
    end

    test "searches products", %{conn: conn, admin: admin, site: site} do
      product_fixture(%{
        organization_id: admin.organization_id,
        site_id: site.id,
        generic_name: "Panadol"
      })

      product_fixture(%{
        organization_id: admin.organization_id,
        site_id: site.id,
        generic_name: "Amoxil"
      })

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")

      assert render(lv) =~ "Panadol"
      assert render(lv) =~ "Amoxil"

      lv
      |> form("form[phx-change='search']", search: "panadol")
      |> render_change()

      html = render(lv)
      assert html =~ "Panadol"
      refute html =~ "Amoxil"
    end
  end

  describe "show" do
    test "displays product details and active batches", %{conn: conn, admin: admin, site: site} do
      product =
        product_fixture(%{
          organization_id: admin.organization_id,
          site_id: site.id,
          generic_name: "Show Me Product",
          price: 99
        })

      _batch =
        batch_fixture(%{
          organization_id: admin.organization_id,
          product_id: product.id,
          site_id: site.id,
          batch_no: "BATCH-001",
          remaining_quantity: 50
        })

      {:ok, lv, html} = live(log_in_user(conn, admin), ~p"/org/products/#{product.id}")

      assert html =~ "Show Me Product"
      assert html =~ "99"
      assert has_element?(lv, "#batches", "BATCH-001")
      assert has_element?(lv, "#batches", "Active")
    end

    test "pending batch shows Pending receipt status", %{conn: conn, admin: admin, site: site} do
      product =
        product_fixture(%{
          organization_id: admin.organization_id,
          site_id: site.id,
          generic_name: "Pending Drug"
        })

      _pending =
        batch_fixture(%{
          organization_id: admin.organization_id,
          product_id: product.id,
          site_id: site.id,
          batch_no: "PENDING-LOT",
          pending: true
        })

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products/#{product.id}")

      assert has_element?(lv, "#batches", "PENDING-LOT")
      assert has_element?(lv, "#batches", "Pending receipt")
    end

    test "admin can add a batch to a product from the show page", %{
      conn: conn,
      admin: admin,
      site: site
    } do
      product =
        product_fixture(%{
          organization_id: admin.organization_id,
          site_id: site.id,
          generic_name: "Batchable Drug",
          gtin: unique_gtin()
        })

      {:ok, lv, _html} =
        live(log_in_user(conn, admin), ~p"/org/products/#{product.id}/batches/new")

      lv
      |> form("#batch-form",
        batch: %{
          site_id: site.id,
          gtin: product.gtin,
          batch_no: "LOT-ADMIN-1",
          expiry_date: "2027-06-01",
          quantity: 200
        }
      )
      |> render_submit()

      assert_patch(lv, ~p"/org/products/#{product.id}")
      html = render(lv)
      assert html =~ "Batch dispatched"
      assert html =~ "LOT-ADMIN-1"
      assert html =~ "200"
    end
  end
end
