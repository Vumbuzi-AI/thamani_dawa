defmodule ThamaniDawaWeb.PharmacyStockLiveTest do
  @moduledoc """
  Covers the acceptance criteria for the site-scoped, read-only stock view:
  staff see every site they're *assigned to* (not just their current one), never
  a site they aren't assigned to and never another organization's stock, the
  site/status filters narrow the list, and the screen exposes no mutation
  controls of its own.

  Admins are org-wide (`site_id: nil`) and get every site in the filter; non-admin
  staff are confined to `user.sites` in both the data and the filter's options.
  """

  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures
  import ThamaniDawa.SuppliersFixtures

  # Builds an organization with one site per name in `site_names` and a pharmacist
  # assigned to all of them. Batches are only visible to non-admin staff at sites
  # they're assigned to, so tests must pin their batches to one of the returned sites.
  defp pharmacist_assigned_to(site_names) do
    admin = user_fixture()
    org_id = admin.organization_id

    sites = Enum.map(site_names, &site_fixture(%{organization_id: org_id, name: &1}))

    pharmacist =
      Map.put(
        staff_fixture(%{
          organization_id: org_id,
          invited_by_id: admin.id,
          role: :pharmacist,
          site_ids: Enum.map(sites, & &1.id)
        }),
        :current_site_id,
        nil
      )

    {org_id, pharmacist, sites}
  end

  describe "access control" do
    test "an admin can reach it", %{conn: conn} do
      admin = user_fixture()

      assert {:ok, _view, _html} =
               live(log_in_user(conn, admin), ~p"/pharmacy/stock?view=batches")
    end

    test "a pharmacist can reach it", %{conn: conn} do
      pharmacist = staff_fixture(%{role: :pharmacist})

      assert {:ok, _view, _html} =
               live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock?view=batches")
    end

    test "combined pharmacy/lab staff can reach it", %{conn: conn} do
      pharma_lab = staff_fixture(%{role: :pharma_lab})

      assert {:ok, _view, _html} =
               live(log_in_user(conn, pharma_lab), ~p"/pharmacy/stock?view=batches")
    end

    test "a lab technician is redirected to the lab portal instead", %{conn: conn} do
      lab_technician = staff_fixture(%{role: :lab_technician})

      assert {:error, {:redirect, %{to: "/lab"}}} =
               live(log_in_user(conn, lab_technician), ~p"/pharmacy/stock?view=batches")
    end

    test "an anonymous visitor is redirected away", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/pharmacy/stock?view=batches")
    end
  end

  describe "assigned-site reads" do
    test "a pharmacist sees batches for their current site", %{conn: conn} do
      {org_id, pharmacist, [site_a, site_b]} = pharmacist_assigned_to(["Site A", "Site B"])

      batch_a =
        batch_fixture(%{organization_id: org_id, site_id: site_a.id, batch_no: "BATCH-SITE-A"})

      batch_b =
        batch_fixture(%{organization_id: org_id, site_id: site_b.id, batch_no: "BATCH-SITE-B"})

      {:ok, _view, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock?view=batches")

      assert html =~ batch_a.batch_no
      refute html =~ batch_b.batch_no
      assert html =~ "Site A"
    end

    test "a pharmacist can neither see nor filter into a site they aren't assigned to", %{
      conn: conn
    } do
      {org_id, pharmacist, [site_a]} = pharmacist_assigned_to(["Site A"])
      off_limits = site_fixture(%{organization_id: org_id, name: "Site Off Limits"})

      mine =
        batch_fixture(%{organization_id: org_id, site_id: site_a.id, batch_no: "BATCH-MINE"})

      theirs =
        batch_fixture(%{
          organization_id: org_id,
          site_id: off_limits.id,
          batch_no: "BATCH-THEIRS"
        })

      {:ok, lv, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock?view=batches")

      assert html =~ mine.batch_no
      refute html =~ theirs.batch_no
      # The filter can't be used to reach it either: it isn't even an option.
      refute html =~ "value=\"#{off_limits.id}\""

      # ...and hand-crafting the filter value is rejected server-side.
      render_click(lv, "set_filter", %{"field" => "site", "value" => "#{off_limits.id}"})
      html = render(lv)

      assert html =~ mine.batch_no
      refute html =~ theirs.batch_no
    end

    test "batches from another organization never appear", %{conn: conn} do
      {org_id, pharmacist, [site_a]} = pharmacist_assigned_to(["Site A"])

      mine = batch_fixture(%{organization_id: org_id, site_id: site_a.id, batch_no: "BATCH-MINE"})

      other_org = organization_fixture()

      other_org_batch =
        batch_fixture(%{organization_id: other_org.id, batch_no: "OTHER-ORG-BATCH"})

      {:ok, _view, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock?view=batches")

      assert html =~ mine.batch_no
      refute html =~ other_org_batch.batch_no
    end

    test "shows both active and pending-receipt batches with their status", %{conn: conn} do
      {org_id, pharmacist, [site_a]} = pharmacist_assigned_to(["Site A"])

      active =
        batch_fixture(%{
          organization_id: org_id,
          site_id: site_a.id,
          batch_no: "ACTIVE-BATCH",
          expiry_date: Date.add(Date.utc_today(), 365)
        })

      pending =
        batch_fixture(%{
          organization_id: org_id,
          site_id: site_a.id,
          batch_no: "PENDING-BATCH",
          pending: true
        })

      {:ok, view, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock?view=batches")

      assert has_element?(view, "#pharmacy-stock-batches", active.batch_no)
      assert has_element?(view, "#pharmacy-stock-batches", "Active")
      assert has_element?(view, "#pharmacy-stock-batches", pending.batch_no)
      assert has_element?(view, "#pharmacy-stock-batches", "Pending receipt")
    end

    test "shows serial, manufacture date, and supplier when present", %{conn: conn} do
      {org_id, pharmacist, [site_a]} = pharmacist_assigned_to(["Site A"])
      supplier = supplier_fixture(%{organization_id: org_id, name: "Bulk Rx"})

      batch_fixture(%{
        organization_id: org_id,
        site_id: site_a.id,
        batch_no: "TRACE-BATCH",
        serial: "SN-77665",
        manufacture_date: ~D[2026-04-01],
        supplier_id: supplier.id
      })

      {:ok, _view, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock?view=batches")

      assert html =~ "SN-77665"
      assert html =~ "1 Apr 2026"
      assert html =~ "Bulk Rx"
    end

    test "shows a dash for serial, manufacture date, and supplier when absent", %{conn: conn} do
      {org_id, pharmacist, [site_a]} = pharmacist_assigned_to(["Site A"])

      batch_fixture(%{organization_id: org_id, site_id: site_a.id, batch_no: "BARE-BATCH"})

      {:ok, view, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock?view=batches")

      assert has_element?(view, "#pharmacy-stock-batches td", "—")
    end
  end

  describe "Products tab" do
    test "an admin sees products with batches, across every site", %{conn: conn} do
      admin = user_fixture()
      org_id = admin.organization_id
      site = site_fixture(%{organization_id: org_id})

      product =
        product_fixture(%{organization_id: org_id, generic_name: "Admin-Visible Product"})

      batch_fixture(%{organization_id: org_id, site_id: site.id, product_id: product.id})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock?view=batches")

      html = render_click(lv, "set_view", %{"view" => "products"})

      assert html =~ "Admin-Visible Product"
    end

    test "a product with only undispatched (org-level) stock is not listed as site stock",
         %{conn: conn} do
      admin = user_fixture()
      org_id = admin.organization_id

      product =
        product_fixture(%{organization_id: org_id, generic_name: "Awaiting Dispatch Product"})

      org_batch_fixture(%{organization_id: org_id, product_id: product.id, quantity: 25})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock?view=batches")

      html = render_click(lv, "set_view", %{"view" => "products"})

      refute html =~ "Awaiting Dispatch Product"
    end

    test "a product at or below reorder_level shows the Low stock or Out of stock badge", %{
      conn: conn
    } do
      {org_id, pharmacist, [site]} = pharmacist_assigned_to(["Site A"])

      low_stock_product =
        product_fixture(%{
          organization_id: org_id,
          generic_name: "Low Stock Drug",
          reorder_level: 10
        })

      batch_fixture(%{
        organization_id: org_id,
        site_id: site.id,
        product_id: low_stock_product.id,
        quantity: 5,
        remaining_quantity: 5,
        expiry_date: Date.add(Date.utc_today(), 365)
      })

      healthy_product =
        product_fixture(%{
          organization_id: org_id,
          generic_name: "Healthy Stock Drug",
          reorder_level: 10
        })

      batch_fixture(%{
        organization_id: org_id,
        site_id: site.id,
        product_id: healthy_product.id,
        quantity: 100,
        remaining_quantity: 100
      })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock?view=batches")
      html = render_click(lv, "set_view", %{"view" => "products"})

      assert html =~ "Low Stock Drug"
      assert html =~ "Low stock"
      assert html =~ "Healthy Stock Drug"
    end
  end

  describe "status filter" do
    test "filters by active", %{conn: conn} do
      {org_id, pharmacist, [site_a]} = pharmacist_assigned_to(["Site A"])

      active =
        batch_fixture(%{organization_id: org_id, site_id: site_a.id, batch_no: "ACTIVE-BATCH"})

      pending =
        batch_fixture(%{
          organization_id: org_id,
          site_id: site_a.id,
          batch_no: "PENDING-BATCH",
          pending: true
        })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock?view=batches")

      render_click(lv, "set_filter", %{"field" => "status", "value" => "active"})

      html = render(lv)
      assert html =~ active.batch_no
      refute html =~ pending.batch_no
    end

    test "setting the status filter back to Any shows every batch again", %{conn: conn} do
      {org_id, pharmacist, [site_a]} = pharmacist_assigned_to(["Site A"])

      active =
        batch_fixture(%{organization_id: org_id, site_id: site_a.id, batch_no: "ACTIVE-BATCH"})

      pending =
        batch_fixture(%{
          organization_id: org_id,
          site_id: site_a.id,
          batch_no: "PENDING-BATCH",
          pending: true
        })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock?view=batches")

      lv |> element("#pharmacy-stock-status-pending") |> render_click()
      assert render(lv) =~ "Status"
      refute render(lv) =~ active.batch_no

      lv |> element("#pharmacy-stock-status-any") |> render_click()

      html = render(lv)
      assert html =~ active.batch_no
      assert html =~ pending.batch_no
    end

    test "filters by pending receipt", %{conn: conn} do
      {org_id, pharmacist, [site_a]} = pharmacist_assigned_to(["Site A"])

      active =
        batch_fixture(%{organization_id: org_id, site_id: site_a.id, batch_no: "ACTIVE-BATCH"})

      pending =
        batch_fixture(%{
          organization_id: org_id,
          site_id: site_a.id,
          batch_no: "PENDING-BATCH",
          pending: true
        })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock?view=batches")

      render_click(lv, "set_filter", %{"field" => "status", "value" => "pending"})

      html = render(lv)
      assert html =~ pending.batch_no
      refute html =~ active.batch_no
    end
  end

  describe "search" do
    test "searches by product name", %{conn: conn} do
      {org_id, pharmacist, [site_a]} = pharmacist_assigned_to(["Site A"])

      panadol = product_fixture(%{organization_id: org_id, generic_name: "Panadol"})
      amoxil = product_fixture(%{organization_id: org_id, generic_name: "Amoxil"})

      panadol_batch =
        batch_fixture(%{organization_id: org_id, site_id: site_a.id, product_id: panadol.id})

      amoxil_batch =
        batch_fixture(%{organization_id: org_id, site_id: site_a.id, product_id: amoxil.id})

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock?view=batches")

      lv |> form("form[phx-change='search']", search: "panadol") |> render_change()

      html = render(lv)
      assert html =~ panadol_batch.batch_no
      refute html =~ amoxil_batch.batch_no
    end
  end

  describe "stock alert tiles" do
    test "summarises out-of-stock, low-stock, and near-expiry stock", %{conn: conn} do
      {org_id, pharmacist, [site]} = pharmacist_assigned_to(["Site A"])

      out_of_stock_product =
        product_fixture(%{
          organization_id: org_id,
          generic_name: "Zero Stock Drug",
          reorder_level: 10
        })

      low_stock_product =
        product_fixture(%{
          organization_id: org_id,
          generic_name: "Low Stock Drug",
          reorder_level: 10
        })

      healthy_product =
        product_fixture(%{
          organization_id: org_id,
          generic_name: "Healthy Stock Drug",
          reorder_level: 10
        })

      batch_fixture(%{
        organization_id: org_id,
        site_id: site.id,
        product_id: out_of_stock_product.id,
        quantity: 5,
        remaining_quantity: 0
      })

      batch_fixture(%{
        organization_id: org_id,
        site_id: site.id,
        product_id: low_stock_product.id,
        quantity: 5,
        remaining_quantity: 5,
        expiry_date: Date.add(Date.utc_today(), 365)
      })

      batch_fixture(%{
        organization_id: org_id,
        site_id: site.id,
        product_id: healthy_product.id,
        quantity: 100,
        remaining_quantity: 100,
        expiry_date: Date.add(Date.utc_today(), 10)
      })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock?view=batches")

      assert has_element?(lv, "#pharmacy-stock-stat-out", "1")
      assert has_element?(lv, "#pharmacy-stock-stat-low", "1")
      assert has_element?(lv, "#pharmacy-stock-stat-near-expiry", "1")
      assert has_element?(lv, "#pharmacy-stock-stat-reorder", "KSh")
    end

    test "pending (unreceived) batches are excluded from the tiles", %{conn: conn} do
      {org_id, pharmacist, [site]} = pharmacist_assigned_to(["Site A"])

      product =
        product_fixture(%{
          organization_id: org_id,
          generic_name: "Pending Only Drug",
          reorder_level: 100
        })

      batch_fixture(%{
        organization_id: org_id,
        site_id: site.id,
        product_id: product.id,
        quantity: 5,
        remaining_quantity: 5,
        expiry_date: Date.add(Date.utc_today(), 10),
        pending: true
      })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock?view=batches")

      assert has_element?(lv, "#pharmacy-stock-stat-out", "0")
      assert has_element?(lv, "#pharmacy-stock-stat-low", "0")
      assert has_element?(lv, "#pharmacy-stock-stat-near-expiry", "0")
    end

    test "the tiles follow the site filter", %{conn: conn} do
      admin = user_fixture()
      org_id = admin.organization_id
      site_a = site_fixture(%{organization_id: org_id, name: "Site A"})
      site_b = site_fixture(%{organization_id: org_id, name: "Site B"})

      product =
        product_fixture(%{
          organization_id: org_id,
          generic_name: "Zero Stock Drug",
          reorder_level: 10
        })

      batch_fixture(%{
        organization_id: org_id,
        site_id: site_a.id,
        product_id: product.id,
        quantity: 5,
        remaining_quantity: 0
      })

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock?view=batches")
      assert has_element?(lv, "#pharmacy-stock-stat-out", "1")

      {:ok, filtered, _html} =
        live(log_in_user(conn, admin), ~p"/pharmacy/stock?site=#{site_b.id}")

      refute has_element?(filtered, "#pharmacy-stock-stat-out", "1")
      assert has_element?(filtered, "#pharmacy-stock-stat-out", "0")
    end
  end

  describe "read-only" do
    test "exposes no receive or dispense controls", %{conn: conn} do
      {org_id, pharmacist, [site_a]} = pharmacist_assigned_to(["Site A"])

      batch_fixture(%{organization_id: org_id, site_id: site_a.id, pending: true})

      {:ok, view, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock?view=batches")

      refute has_element?(view, "#stock form")
      refute has_element?(view, "button", "Receive")
      refute has_element?(view, "button", "Dispense")
    end
  end
end
