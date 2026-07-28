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
      staff_fixture(%{
        organization_id: org_id,
        invited_by_id: admin.id,
        role: :pharmacist,
        site_ids: Enum.map(sites, & &1.id)
      })

    {org_id, pharmacist, sites}
  end

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

    test "a lab technician is redirected to the lab portal instead", %{conn: conn} do
      lab_technician = staff_fixture(%{role: :lab_technician})

      assert {:error, {:redirect, %{to: "/lab"}}} =
               live(log_in_user(conn, lab_technician), ~p"/pharmacy/stock")
    end

    test "an anonymous visitor is redirected away", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/pharmacy/stock")
    end
  end

  describe "assigned-site reads" do
    test "a pharmacist sees batches at every site they're assigned to", %{conn: conn} do
      {org_id, pharmacist, [site_a, site_b]} = pharmacist_assigned_to(["Site A", "Site B"])

      batch_a =
        batch_fixture(%{organization_id: org_id, site_id: site_a.id, batch_no: "BATCH-SITE-A"})

      batch_b =
        batch_fixture(%{organization_id: org_id, site_id: site_b.id, batch_no: "BATCH-SITE-B"})

      {:ok, _view, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")

      assert html =~ batch_a.batch_no
      assert html =~ batch_b.batch_no
      assert html =~ "Site A"
      assert html =~ "Site B"
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

      {:ok, lv, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")

      assert html =~ mine.batch_no
      refute html =~ theirs.batch_no
      # The filter can't be used to reach it either: it isn't even an option.
      refute html =~ "value=\"#{off_limits.id}\""

      # ...and hand-crafting the filter value is rejected server-side.
      html = render_submit(lv, "apply_filters", %{"filters" => %{"site" => "#{off_limits.id}"}})

      assert html =~ mine.batch_no
      refute html =~ theirs.batch_no
    end

    test "batches from another organization never appear", %{conn: conn} do
      {org_id, pharmacist, [site_a]} = pharmacist_assigned_to(["Site A"])

      mine = batch_fixture(%{organization_id: org_id, site_id: site_a.id, batch_no: "BATCH-MINE"})

      other_org = organization_fixture()

      other_org_batch =
        batch_fixture(%{organization_id: other_org.id, batch_no: "OTHER-ORG-BATCH"})

      {:ok, _view, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")

      assert html =~ mine.batch_no
      refute html =~ other_org_batch.batch_no
    end

    test "shows both active and pending-receipt batches with their status", %{conn: conn} do
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

      {:ok, view, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")

      assert has_element?(view, "#stock", active.batch_no)
      assert has_element?(view, "#stock", "Active")
      assert has_element?(view, "#stock", pending.batch_no)
      assert has_element?(view, "#stock", "Pending receipt")
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

      {:ok, _view, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")

      assert html =~ "SN-77665"
      assert html =~ "2026-04-01"
      assert html =~ "Bulk Rx"
    end

    test "shows a dash for serial, manufacture date, and supplier when absent", %{conn: conn} do
      {org_id, pharmacist, [site_a]} = pharmacist_assigned_to(["Site A"])

      batch_fixture(%{organization_id: org_id, site_id: site_a.id, batch_no: "BARE-BATCH"})

      {:ok, view, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")

      assert has_element?(view, "#stock td", "—")
    end
  end

  describe "site filter" do
    test "narrows the list to just the selected site", %{conn: conn} do
      {org_id, pharmacist, [site_a, site_b]} = pharmacist_assigned_to(["Site A", "Site B"])

      batch_a =
        batch_fixture(%{organization_id: org_id, site_id: site_a.id, batch_no: "BATCH-SITE-A"})

      batch_b =
        batch_fixture(%{organization_id: org_id, site_id: site_b.id, batch_no: "BATCH-SITE-B"})

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")

      lv
      |> form("#stock-filters-form", filters: %{site: to_string(site_a.id)})
      |> render_submit()

      html = render(lv)
      assert html =~ batch_a.batch_no
      refute html =~ batch_b.batch_no
      assert html =~ "Site: Site A"
    end

    test "clear_filters shows every assigned site again", %{conn: conn} do
      {org_id, pharmacist, [site_a, site_b]} = pharmacist_assigned_to(["Site A", "Site B"])

      batch_a =
        batch_fixture(%{organization_id: org_id, site_id: site_a.id, batch_no: "BATCH-SITE-A"})

      batch_b =
        batch_fixture(%{organization_id: org_id, site_id: site_b.id, batch_no: "BATCH-SITE-B"})

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
      {org_id, pharmacist, [site_a, site_b]} = pharmacist_assigned_to(["Site A", "Site B"])

      batch_a =
        batch_fixture(%{organization_id: org_id, site_id: site_a.id, batch_no: "BATCH-SITE-A"})

      batch_b =
        batch_fixture(%{organization_id: org_id, site_id: site_b.id, batch_no: "BATCH-SITE-B"})

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

    test "a malformed site filter is ignored rather than crashing, for staff and admin", %{
      conn: conn
    } do
      {org_id, pharmacist, [site_a]} = pharmacist_assigned_to(["Site A"])
      batch = batch_fixture(%{organization_id: org_id, site_id: site_a.id})

      # Staff path: `sanitize_site_filter/2` used to raise on a non-numeric value.
      {:ok, staff_lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")
      html = render_submit(staff_lv, "apply_filters", %{"filters" => %{"site" => "abc"}})
      assert html =~ batch.batch_no

      # Admin path: the value reached `Batches.filter_by_site_opt/2` unsanitised.
      admin = user_fixture(%{organization_id: org_id})
      {:ok, admin_lv, _html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock")
      html = render_submit(admin_lv, "apply_filters", %{"filters" => %{"site" => "abc"}})
      assert html =~ batch.batch_no
    end

    test "for an admin, a stale site filter falls back to showing its raw id", %{conn: conn} do
      # Admins are org-wide, so their filter value isn't narrowed to an assigned
      # set — a since-deleted site id survives and is shown as-is on the chip.
      admin = user_fixture()
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock")

      html = render_submit(lv, "apply_filters", %{"filters" => %{"site" => "999999"}})

      assert html =~ "Site: 999999"
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

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")

      lv
      |> form("#stock-filters-form", filters: %{status: "active"})
      |> render_submit()

      html = render(lv)
      assert html =~ active.batch_no
      refute html =~ pending.batch_no
    end

    test "clearing the status filter chip removes just that filter", %{conn: conn} do
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
      {org_id, pharmacist, [site_a]} = pharmacist_assigned_to(["Site A"])

      panadol = product_fixture(%{organization_id: org_id, generic_name: "Panadol"})
      amoxil = product_fixture(%{organization_id: org_id, generic_name: "Amoxil"})

      panadol_batch =
        batch_fixture(%{organization_id: org_id, site_id: site_a.id, product_id: panadol.id})

      amoxil_batch =
        batch_fixture(%{organization_id: org_id, site_id: site_a.id, product_id: amoxil.id})

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")

      lv |> form("form[phx-change='search']", search: "panadol") |> render_change()

      html = render(lv)
      assert html =~ panadol_batch.batch_no
      refute html =~ amoxil_batch.batch_no
    end
  end

  describe "read-only" do
    test "exposes no receive or dispense controls", %{conn: conn} do
      {org_id, pharmacist, [site_a]} = pharmacist_assigned_to(["Site A"])

      batch_fixture(%{organization_id: org_id, site_id: site_a.id, pending: true})

      {:ok, view, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock")

      refute has_element?(view, "#stock form")
      refute has_element?(view, "button", "Receive")
      refute has_element?(view, "button", "Dispense")
    end
  end
end
