defmodule ThamaniDawaWeb.PharmacyStockLiveTest do
  @moduledoc """
  Covers the acceptance criteria for the organization-wide, read-only stock
  view: pharmacists see every site's batches (not just their home site),
  cross-organization stock never leaks in, site/status filters narrow the
  list, and the screen exposes no mutation controls of its own.
  """

  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures
  import ThamaniDawa.SuppliersFixtures

  describe "access control" do
    test "an admin can reach it", %{conn: conn} do
      admin = user_fixture()
      assert {:ok, _view, _html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock")
    end

    test "a pharmacist can reach it", %{conn: conn} do
      pharmacist = staff_fixture(%{role: :pharmacist})
      assert {:ok, _view, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")
    end

    test "combined pharmacy/lab staff can reach it", %{conn: conn} do
      pharma_lab = staff_fixture(%{role: :pharma_lab})
      assert {:ok, _view, _html} = live(log_in_user(conn, pharma_lab), ~p"/pharmacy/stock")
    end

    test "a lab technician is redirected away", %{conn: conn} do
      lab_technician = staff_fixture(%{role: :lab_technician})

      assert {:error, {:redirect, %{to: "/"}}} =
               live(log_in_user(conn, lab_technician), ~p"/pharmacy/stock")
    end

    test "an anonymous visitor is redirected away", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/pharmacy/stock")
    end
  end

  describe "organization-wide reads" do
    test "a pharmacist sees batches at every site, not just their home site", %{conn: conn} do
      admin = user_fixture()
      site_a = site_fixture(%{organization_id: admin.organization_id, name: "Site A"})
      site_b = site_fixture(%{organization_id: admin.organization_id, name: "Site B"})

      pharmacist =
        staff_fixture(%{
          organization_id: admin.organization_id,
          invited_by_id: admin.id,
          role: :pharmacist,
          site_id: site_a.id
        })

      batch_a =
        batch_fixture(%{
          organization_id: admin.organization_id,
          site_id: site_a.id,
          batch_no: "BATCH-SITE-A"
        })

      batch_b =
        batch_fixture(%{
          organization_id: admin.organization_id,
          site_id: site_b.id,
          batch_no: "BATCH-SITE-B"
        })

      {:ok, _view, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")

      assert html =~ batch_a.batch_no
      assert html =~ batch_b.batch_no
      assert html =~ "Site A"
      assert html =~ "Site B"
    end

    test "batches from another organization never appear", %{conn: conn} do
      pharmacist = staff_fixture(%{role: :pharmacist})

      other_org = organization_fixture()

      other_org_batch =
        batch_fixture(%{organization_id: other_org.id, batch_no: "OTHER-ORG-BATCH"})

      {:ok, _view, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")

      refute html =~ other_org_batch.batch_no
    end

    test "shows both active and pending-receipt batches with their status", %{conn: conn} do
      pharmacist = staff_fixture(%{role: :pharmacist})

      active =
        batch_fixture(%{organization_id: pharmacist.organization_id, batch_no: "ACTIVE-BATCH"})

      pending =
        batch_fixture(%{
          organization_id: pharmacist.organization_id,
          batch_no: "PENDING-BATCH",
          pending: true
        })

      {:ok, view, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")

      assert has_element?(view, "#stock", active.batch_no)
      assert has_element?(view, "#stock", "Active")
      assert has_element?(view, "#stock", pending.batch_no)
      assert has_element?(view, "#stock", "Pending receipt")
    end

    test "shows serial, manufacture date, and supplier when present", %{conn: conn} do
      pharmacist = staff_fixture(%{role: :pharmacist})
      supplier = supplier_fixture(%{organization_id: pharmacist.organization_id, name: "Bulk Rx"})

      batch_fixture(%{
        organization_id: pharmacist.organization_id,
        batch_no: "TRACE-BATCH",
        serial: "SN-77665",
        manufacture_date: ~D[2026-04-01],
        supplier_id: supplier.id
      })

      {:ok, _view, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")

      assert html =~ "SN-77665"
      assert html =~ "2026-04-01"
      assert html =~ "Bulk Rx"
    end

    test "shows a dash for serial, manufacture date, and supplier when absent", %{conn: conn} do
      pharmacist = staff_fixture(%{role: :pharmacist})

      batch_fixture(%{organization_id: pharmacist.organization_id, batch_no: "BARE-BATCH"})

      {:ok, view, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")

      assert has_element?(view, "#stock td", "—")
    end
  end

  describe "site filter" do
    test "narrows the list to just the selected site", %{conn: conn} do
      admin = user_fixture()
      site_a = site_fixture(%{organization_id: admin.organization_id, name: "Site A"})
      site_b = site_fixture(%{organization_id: admin.organization_id, name: "Site B"})
      pharmacist = staff_fixture(%{organization_id: admin.organization_id, role: :pharmacist})

      batch_a =
        batch_fixture(%{
          organization_id: admin.organization_id,
          site_id: site_a.id,
          batch_no: "BATCH-SITE-A"
        })

      batch_b =
        batch_fixture(%{
          organization_id: admin.organization_id,
          site_id: site_b.id,
          batch_no: "BATCH-SITE-B"
        })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")

      lv
      |> form("#stock-filters-form", filters: %{site: to_string(site_a.id)})
      |> render_submit()

      html = render(lv)
      assert html =~ batch_a.batch_no
      refute html =~ batch_b.batch_no
      assert html =~ "Site: Site A"
    end

    test "clear_filters shows every site again", %{conn: conn} do
      admin = user_fixture()
      site_a = site_fixture(%{organization_id: admin.organization_id, name: "Site A"})
      site_b = site_fixture(%{organization_id: admin.organization_id, name: "Site B"})
      pharmacist = staff_fixture(%{organization_id: admin.organization_id, role: :pharmacist})

      batch_a =
        batch_fixture(%{
          organization_id: admin.organization_id,
          site_id: site_a.id,
          batch_no: "BATCH-SITE-A"
        })

      batch_b =
        batch_fixture(%{
          organization_id: admin.organization_id,
          site_id: site_b.id,
          batch_no: "BATCH-SITE-B"
        })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")

      lv
      |> form("#stock-filters-form", filters: %{site: to_string(site_a.id)})
      |> render_submit()

      refute render(lv) =~ batch_b.batch_no

      lv |> element("button", "Clear filters") |> render_click()

      html = render(lv)
      assert html =~ batch_a.batch_no
      assert html =~ batch_b.batch_no
    end

    test "clearing the site filter chip removes just that filter", %{conn: conn} do
      admin = user_fixture()
      site_a = site_fixture(%{organization_id: admin.organization_id, name: "Site A"})
      site_b = site_fixture(%{organization_id: admin.organization_id, name: "Site B"})
      pharmacist = staff_fixture(%{organization_id: admin.organization_id, role: :pharmacist})

      batch_a =
        batch_fixture(%{
          organization_id: admin.organization_id,
          site_id: site_a.id,
          batch_no: "BATCH-SITE-A"
        })

      batch_b =
        batch_fixture(%{
          organization_id: admin.organization_id,
          site_id: site_b.id,
          batch_no: "BATCH-SITE-B"
        })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")

      lv
      |> form("#stock-filters-form", filters: %{site: to_string(site_a.id)})
      |> render_submit()

      lv
      |> element("button[aria-label='Remove Site: Site A filter']")
      |> render_click()

      html = render(lv)
      assert html =~ batch_a.batch_no
      assert html =~ batch_b.batch_no
    end

    test "a stale site filter (no longer a real site) falls back to showing its raw id", %{
      conn: conn
    } do
      pharmacist = staff_fixture(%{role: :pharmacist})
      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")

      html = render_submit(lv, "apply_filters", %{"filters" => %{"site" => "999999"}})

      assert html =~ "Site: 999999"
    end
  end

  describe "status filter" do
    test "filters by active", %{conn: conn} do
      pharmacist = staff_fixture(%{role: :pharmacist})

      active =
        batch_fixture(%{organization_id: pharmacist.organization_id, batch_no: "ACTIVE-BATCH"})

      pending =
        batch_fixture(%{
          organization_id: pharmacist.organization_id,
          batch_no: "PENDING-BATCH",
          pending: true
        })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")

      lv
      |> form("#stock-filters-form", filters: %{status: "active"})
      |> render_submit()

      html = render(lv)
      assert html =~ active.batch_no
      refute html =~ pending.batch_no
    end

    test "clearing the status filter chip removes just that filter", %{conn: conn} do
      pharmacist = staff_fixture(%{role: :pharmacist})

      active =
        batch_fixture(%{organization_id: pharmacist.organization_id, batch_no: "ACTIVE-BATCH"})

      pending =
        batch_fixture(%{
          organization_id: pharmacist.organization_id,
          batch_no: "PENDING-BATCH",
          pending: true
        })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")

      lv
      |> form("#stock-filters-form", filters: %{status: "pending"})
      |> render_submit()

      lv
      |> element("button[aria-label='Remove Status: Pending filter']")
      |> render_click()

      html = render(lv)
      assert html =~ active.batch_no
      assert html =~ pending.batch_no
    end

    test "filters by pending receipt", %{conn: conn} do
      pharmacist = staff_fixture(%{role: :pharmacist})

      active =
        batch_fixture(%{organization_id: pharmacist.organization_id, batch_no: "ACTIVE-BATCH"})

      pending =
        batch_fixture(%{
          organization_id: pharmacist.organization_id,
          batch_no: "PENDING-BATCH",
          pending: true
        })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")

      lv
      |> form("#stock-filters-form", filters: %{status: "pending"})
      |> render_submit()

      html = render(lv)
      assert html =~ pending.batch_no
      refute html =~ active.batch_no
    end
  end

  describe "search" do
    test "searches by product name", %{conn: conn} do
      pharmacist = staff_fixture(%{role: :pharmacist})

      panadol =
        product_fixture(%{
          organization_id: pharmacist.organization_id,
          generic_name: "Panadol"
        })

      amoxil =
        product_fixture(%{
          organization_id: pharmacist.organization_id,
          generic_name: "Amoxil"
        })

      panadol_batch =
        batch_fixture(%{organization_id: pharmacist.organization_id, product_id: panadol.id})

      amoxil_batch =
        batch_fixture(%{organization_id: pharmacist.organization_id, product_id: amoxil.id})

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")

      lv |> form("form[phx-change='search']", search: "panadol") |> render_change()

      html = render(lv)
      assert html =~ panadol_batch.batch_no
      refute html =~ amoxil_batch.batch_no
    end
  end

  describe "read-only" do
    test "exposes no receive or dispense controls", %{conn: conn} do
      pharmacist = staff_fixture(%{role: :pharmacist})
      batch_fixture(%{organization_id: pharmacist.organization_id, pending: true})

      {:ok, view, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")

      refute has_element?(view, "#stock form")
      refute has_element?(view, "button", "Receive")
      refute has_element?(view, "button", "Dispense")
    end
  end
end
