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

  defp skip_gtin_scan(lv) do
    lv |> form("#gtin-scan-form", gtin_search: "") |> render_submit()
  end

  describe "index" do
    test "lists products for the organization", %{conn: conn, admin: admin} do
      _product =
        product_fixture(%{
          organization_id: admin.organization_id,
          generic_name: "Test Aspirin"
        })

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/products")

      assert html =~ "Test Aspirin"
    end

    test "renders sidebar with correct hook for persistence", %{conn: conn, admin: admin} do
      {:ok, lv, html} = live(log_in_user(conn, admin), ~p"/org/products")

      assert has_element?(lv, "#sidebar-shell")
      assert has_element?(lv, "#sidebar-toggle")
      assert has_element?(lv, "#sidebar-aside")
      assert html =~ "Sidebar"
    end

    test "opens the add-product modal and closes it again on cancel", %{
      conn: conn,
      admin: admin
    } do
      {:ok, lv, html} = live(log_in_user(conn, admin), ~p"/org/products")
      assert html =~ "+ Add product"
      refute has_element?(lv, "#product-modal")

      html = lv |> element("a", "+ Add product") |> render_click()

      assert has_element?(lv, "#product-modal")
      assert html =~ "Add a product"
      assert html =~ "+ Add product"

      html = lv |> element("#product-modal a", "Cancel") |> render_click()

      refute has_element?(lv, "#product-modal")
      assert html =~ "+ Add product"
    end

    test "creates a new product", %{conn: conn, admin: admin} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")

      lv |> element("a", "+ Add product") |> render_click()
      skip_gtin_scan(lv)

      lv
      |> form("form[phx-submit='save']",
        product: %{
          generic_name: "New Panadol",
          brand_name: "Panadol",
          category: "Painkiller",
          uom: "Pack",
          gtin: unique_gtin(),
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
      admin: admin
    } do
      product =
        product_fixture(%{
          organization_id: admin.organization_id,
          generic_name: "Old Name"
        })

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")

      lv |> element("#products-#{product.id} a", "Edit") |> render_click()

      lv
      |> form("form[phx-submit='save']",
        product: %{
          price: "100",
          generic_name: "Updated Name"
        }
      )
      |> render_submit()

      html = render(lv)
      assert html =~ "Product updated."
      assert html =~ "Updated Name"
      refute html =~ "Old Name"

      assert html |> String.split("id=\"products-#{product.id}\"") |> length() == 2
    end

    test "searches products", %{conn: conn, admin: admin} do
      product_fixture(%{organization_id: admin.organization_id, generic_name: "Panadol"})
      product_fixture(%{organization_id: admin.organization_id, generic_name: "Amoxil"})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")

      assert render(lv) =~ "Panadol"
      assert render(lv) =~ "Amoxil"

      lv |> form("form[phx-change='search']", search: "panadol") |> render_change()

      html = render(lv)
      assert html =~ "Panadol"
      refute html =~ "Amoxil"
    end

    test "clearing the search box shows every product again", %{conn: conn, admin: admin} do
      product_fixture(%{organization_id: admin.organization_id, generic_name: "Panadol"})
      product_fixture(%{organization_id: admin.organization_id, generic_name: "Amoxil"})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")

      lv |> form("form[phx-change='search']", search: "panadol") |> render_change()
      refute render(lv) =~ "Amoxil"

      lv |> form("form[phx-change='search']", search: "") |> render_change()

      html = render(lv)
      assert html =~ "Panadol"
      assert html =~ "Amoxil"
    end

    test "filters by category", %{conn: conn, admin: admin} do
      product_fixture(%{
        organization_id: admin.organization_id,
        generic_name: "Panadol",
        category: "Painkiller"
      })

      product_fixture(%{
        organization_id: admin.organization_id,
        generic_name: "Amoxil",
        category: "Antibiotic"
      })

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")

      lv
      |> form("#products-filters-form", filters: %{category: "Painkiller"})
      |> render_submit()

      html = render(lv)
      assert html =~ "Panadol"
      refute html =~ "Amoxil"
      assert html =~ "Category: Painkiller"
    end

    test "filters by the over-the-counter flag", %{conn: conn, admin: admin} do
      product_fixture(%{
        organization_id: admin.organization_id,
        generic_name: "Panadol",
        is_otc: true
      })

      product_fixture(%{
        organization_id: admin.organization_id,
        generic_name: "Amoxil",
        is_otc: false
      })

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")

      lv
      |> form("#products-filters-form", filters: %{is_otc: "true", is_dangerous_drug: "false"})
      |> render_submit()

      html = render(lv)
      assert html =~ "Panadol"
      refute html =~ "Amoxil"
    end

    test "clear_filters resets category and flag filters", %{conn: conn, admin: admin} do
      product_fixture(%{
        organization_id: admin.organization_id,
        generic_name: "Panadol",
        category: "Painkiller"
      })

      product_fixture(%{
        organization_id: admin.organization_id,
        generic_name: "Amoxil",
        category: "Antibiotic"
      })

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")

      lv
      |> form("#products-filters-form", filters: %{category: "Painkiller"})
      |> render_submit()

      refute render(lv) =~ "Amoxil"

      lv |> element("button", "Clear filters") |> render_click()

      html = render(lv)
      assert html =~ "Panadol"
      assert html =~ "Amoxil"
    end

    test "search and category filters combine", %{conn: conn, admin: admin} do
      product_fixture(%{
        organization_id: admin.organization_id,
        generic_name: "Panadol Extra",
        category: "Painkiller"
      })

      product_fixture(%{
        organization_id: admin.organization_id,
        generic_name: "Panadol Kids",
        category: "Painkiller"
      })

      product_fixture(%{
        organization_id: admin.organization_id,
        generic_name: "Amoxil",
        category: "Antibiotic"
      })

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")

      lv
      |> form("#products-filters-form", filters: %{category: "Painkiller"})
      |> render_submit()

      lv |> form("form[phx-change='search']", search: "extra") |> render_change()

      html = render(lv)
      assert html =~ "Panadol Extra"
      refute html =~ "Panadol Kids"
      refute html =~ "Amoxil"
    end

    test "live-validates the new product form", %{conn: conn, admin: admin} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")

      lv |> element("a", "+ Add product") |> render_click()
      skip_gtin_scan(lv)

      html =
        lv
        |> form("form[phx-submit='save']", product: %{generic_name: "Panadol", price: ""})
        |> render_change()

      assert html =~ "can&#39;t be blank"
    end

    test "a non-numeric GTIN shows a validation error instead of crashing", %{
      conn: conn,
      admin: admin
    } do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")

      lv |> element("a", "+ Add product") |> render_click()
      skip_gtin_scan(lv)

      html =
        lv
        |> form("form[phx-submit='save']",
          product: %{generic_name: "Panadol", uom: "tablet", price: "50", gtin: "abc"}
        )
        |> render_change()

      assert html =~ "is not a valid GTIN"
    end

    test "shows an error and does not create a product when required fields are missing", %{
      conn: conn,
      admin: admin
    } do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")

      lv |> element("a", "+ Add product") |> render_click()
      skip_gtin_scan(lv)

      html =
        lv
        |> form("form[phx-submit='save']", product: %{generic_name: "No Price Drug", price: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"

      refute Enum.any?(
               ThamaniDawa.Products.list_products(admin.organization_id),
               &(&1.generic_name == "No Price Drug")
             )
    end

    test "shows an error and does not create a product with no name at all", %{
      conn: conn,
      admin: admin
    } do
      before_count = length(ThamaniDawa.Products.list_products(admin.organization_id))

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")

      lv |> element("a", "+ Add product") |> render_click()
      skip_gtin_scan(lv)

      html =
        lv
        |> form("form[phx-submit='save']", product: %{price: "50"})
        |> render_submit()

      assert html =~ "enter a generic or brand name"
      assert length(ThamaniDawa.Products.list_products(admin.organization_id)) == before_count
    end

    test "shows an error and does not persist an invalid edit", %{conn: conn, admin: admin} do
      product =
        product_fixture(%{organization_id: admin.organization_id, generic_name: "Keep Me"})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")

      lv |> element("#products-#{product.id} a", "Edit") |> render_click()

      html =
        lv
        |> form("form[phx-submit='save']", product: %{price: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"

      assert %{generic_name: "Keep Me"} =
               ThamaniDawa.Products.get_product!(admin.organization_id, product.id)
    end
  end

  describe "GTIN lookup" do
    test "adding a product starts at the scan step, not the form", %{conn: conn, admin: admin} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")

      lv |> element("a", "+ Add product") |> render_click()

      assert has_element?(lv, "#gtin-scan-step")
      refute has_element?(lv, "#product-form")
    end

    test "editing an existing product skips the scan step and goes straight to the form", %{
      conn: conn,
      admin: admin
    } do
      product = product_fixture(%{organization_id: admin.organization_id})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products/#{product.id}/edit")

      refute has_element?(lv, "#gtin-scan-step")
      assert has_element?(lv, "#product-form")
    end

    test "the scan box echoes back what's typed", %{conn: conn, admin: admin} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")

      lv |> element("a", "+ Add product") |> render_click()

      html =
        lv
        |> form("#gtin-scan-form", gtin_search: "123")
        |> render_change()

      assert html =~ ~s(value="123")
    end

    test "a crashed lookup task shows the provider-error state", %{conn: conn, admin: admin} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")
      Req.Test.allow(ThamaniDawa.GtinLookup, self(), lv.pid)

      Req.Test.stub(ThamaniDawa.GtinLookup, fn _conn -> raise "boom" end)

      lv |> element("a", "+ Add product") |> render_click()

      lv
      |> form("#gtin-scan-form", gtin_search: unique_gtin())
      |> render_submit()

      html = render_async(lv)

      assert html =~ "Couldn&#39;t reach the lookup service"
    end

    test "a match prefills only the supported fields for review before save", %{
      conn: conn,
      admin: admin
    } do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")
      Req.Test.allow(ThamaniDawa.GtinLookup, self(), lv.pid)

      Req.Test.stub(ThamaniDawa.GtinLookup, fn conn ->
        Req.Test.json(conn, [
          %{
            "brandName" => [%{"value" => "Panadol"}],
            "productDescription" => [%{"value" => "Paracetamol 500mg Tablets"}],
            "gs1Licence" => %{"licenseeName" => "GlaxoSmithKline"},
            "netContent" => [%{"value" => "100", "unitCode" => "H87"}]
          }
        ])
      end)

      lv |> element("a", "+ Add product") |> render_click()

      lv
      |> form("#gtin-scan-form", gtin_search: unique_gtin())
      |> render_submit()

      html = render_async(lv)

      assert has_element?(lv, "#product-form")
      refute has_element?(lv, "#gtin-scan-step")
      assert html =~ "Match found"
      assert html =~ "Panadol"
      assert html =~ "Paracetamol 500mg Tablets"
      assert html =~ "GlaxoSmithKline"

      refute Enum.any?(
               ThamaniDawa.Products.list_products(admin.organization_id),
               &(&1.brand_name == "Panadol")
             )
    end

    test "no match still advances to the form, prefilled with just the scanned GTIN", %{
      conn: conn,
      admin: admin
    } do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")
      Req.Test.allow(ThamaniDawa.GtinLookup, self(), lv.pid)

      Req.Test.stub(ThamaniDawa.GtinLookup, fn conn -> Req.Test.json(conn, []) end)

      gtin = unique_gtin()

      lv |> element("a", "+ Add product") |> render_click()

      lv
      |> form("#gtin-scan-form", gtin_search: gtin)
      |> render_submit()

      html = render_async(lv)

      assert html =~ "No match found for this GTIN"
      assert has_element?(lv, "#product-form")
      assert html =~ gtin
      assert ThamaniDawa.Products.list_products(admin.organization_id) == []
    end

    test "a provider error still advances to the form, no product created", %{
      conn: conn,
      admin: admin
    } do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")
      Req.Test.allow(ThamaniDawa.GtinLookup, self(), lv.pid)

      Req.Test.stub(ThamaniDawa.GtinLookup, fn conn -> Plug.Conn.send_resp(conn, 500, "") end)

      lv |> element("a", "+ Add product") |> render_click()

      lv
      |> form("#gtin-scan-form", gtin_search: unique_gtin())
      |> render_submit()

      html = render_async(lv)

      assert html =~ "Couldn&#39;t reach the lookup service"
      assert has_element?(lv, "#product-form")
      assert ThamaniDawa.Products.list_products(admin.organization_id) == []
    end

    test "a timed-out lookup still advances to the form, no product created", %{
      conn: conn,
      admin: admin
    } do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")
      Req.Test.allow(ThamaniDawa.GtinLookup, self(), lv.pid)

      Req.Test.stub(ThamaniDawa.GtinLookup, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      lv |> element("a", "+ Add product") |> render_click()

      lv
      |> form("#gtin-scan-form", gtin_search: unique_gtin())
      |> render_submit()

      html = render_async(lv)

      assert html =~ "Lookup timed out"
      assert has_element?(lv, "#product-form")
      assert ThamaniDawa.Products.list_products(admin.organization_id) == []
    end

    test "an invalid GTIN shows a validation message instantly and stays on the scan step", %{
      conn: conn,
      admin: admin
    } do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")

      lv |> element("a", "+ Add product") |> render_click()

      html =
        lv
        |> form("#gtin-scan-form", gtin_search: "not-a-gtin")
        |> render_submit()

      assert html =~ "is not a valid GTIN"
      assert has_element?(lv, "#gtin-scan-step")
      refute has_element?(lv, "#product-form")
    end

    test "continuing without a GTIN advances straight to the form for manual entry", %{
      conn: conn,
      admin: admin
    } do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products")

      lv |> element("a", "+ Add product") |> render_click()

      html =
        lv
        |> form("#gtin-scan-form", gtin_search: "")
        |> render_submit()

      assert has_element?(lv, "#product-form")
      refute has_element?(lv, "#gtin-scan-step")
      refute html =~ "is not a valid GTIN"
    end
  end

  describe "show" do
    test "displays product details and active batches", %{conn: conn, admin: admin, site: site} do
      product =
        product_fixture(%{
          organization_id: admin.organization_id,
          generic_name: "Show Me Product",
          manufacturer: "GlaxoSmithKline",
          price: 99
        })

      _batch =
        batch_fixture(%{
          organization_id: admin.organization_id,
          site_id: site.id,
          product_id: product.id,
          batch_no: "BATCH-001",
          remaining_quantity: 50
        })

      {:ok, lv, html} = live(log_in_user(conn, admin), ~p"/org/products/#{product.id}")

      assert html =~ "Show Me Product"
      assert html =~ "99"
      assert html =~ "GlaxoSmithKline"
      assert has_element?(lv, "#batches", "BATCH-001")
      assert has_element?(lv, "#batches", "Active")
    end

    test "pending batch shows Pending receipt status", %{conn: conn, admin: admin, site: site} do
      product =
        product_fixture(%{
          organization_id: admin.organization_id,
          generic_name: "Pending Drug"
        })

      _pending =
        batch_fixture(%{
          organization_id: admin.organization_id,
          site_id: site.id,
          product_id: product.id,
          batch_no: "PENDING-LOT",
          pending: true
        })

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/products/#{product.id}")

      assert has_element?(lv, "#batches", "PENDING-LOT")
      assert has_element?(lv, "#batches", "Pending receipt")
    end

    test "admin can dispatch a batch to a site from the show page", %{
      conn: conn,
      admin: admin,
      site: site
    } do
      product =
        product_fixture(%{
          organization_id: admin.organization_id,
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

    test "shows an error dispatching the same batch_no to the same site twice", %{
      conn: conn,
      admin: admin,
      site: site
    } do
      product =
        product_fixture(%{organization_id: admin.organization_id, gtin: unique_gtin()})

      batch_fixture(%{
        organization_id: admin.organization_id,
        product_id: product.id,
        site_id: site.id,
        gtin: product.gtin,
        batch_no: "LOT-REPEAT"
      })

      {:ok, lv, _html} =
        live(log_in_user(conn, admin), ~p"/org/products/#{product.id}/batches/new")

      html =
        lv
        |> form("#batch-form",
          batch: %{
            site_id: site.id,
            gtin: product.gtin,
            batch_no: "LOT-REPEAT",
            expiry_date: "2027-06-01",
            quantity: 50
          }
        )
        |> render_submit()

      assert html =~ "has already been dispatched to this site"

      assert length(
               ThamaniDawa.Batches.list_batches_for_product(admin.organization_id, product.id)
             ) == 1
    end

    test "live-validates the dispatch batch form", %{conn: conn, admin: admin, site: site} do
      product = product_fixture(%{organization_id: admin.organization_id})

      {:ok, lv, _html} =
        live(log_in_user(conn, admin), ~p"/org/products/#{product.id}/batches/new")

      html =
        lv
        |> form("#batch-form", batch: %{site_id: site.id, batch_no: ""})
        |> render_change()

      assert html =~ "can&#39;t be blank"
    end

    test "shows an error and does not dispatch a batch with an invalid GTIN", %{
      conn: conn,
      admin: admin,
      site: site
    } do
      product = product_fixture(%{organization_id: admin.organization_id})

      {:ok, lv, _html} =
        live(log_in_user(conn, admin), ~p"/org/products/#{product.id}/batches/new")

      html =
        lv
        |> form("#batch-form",
          batch: %{
            site_id: site.id,
            gtin: "00614141000011",
            batch_no: "LOT-BAD-GTIN",
            expiry_date: "2027-06-01",
            quantity: 10
          }
        )
        |> render_submit()

      assert html =~ "is not a valid GTIN"

      assert ThamaniDawa.Batches.list_batches_for_product(admin.organization_id, product.id) == []
    end
  end
end
