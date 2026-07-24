defmodule ThamaniDawaWeb.LabReceiveStockLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures
  import ThamaniDawa.SuppliersFixtures

  setup do
    admin = user_fixture()
    org_id = admin.organization_id

    lab_site = site_fixture(%{organization_id: org_id, site_type: :lab})
    pharmacy_site = site_fixture(%{organization_id: org_id, site_type: :pharmacy})

    lab_tech =
      staff_fixture(%{
        role: :lab_technician,
        organization_id: org_id,
        site_id: lab_site.id
      })

    {:ok,
     admin: admin,
     lab_tech: lab_tech,
     lab_site: lab_site,
     pharmacy_site: pharmacy_site,
     org_id: org_id}
  end

  describe "pending deliveries" do
    test "lab tech sees pending batch dispatched to their site", %{
      conn: conn,
      lab_tech: lab_tech,
      lab_site: lab_site,
      org_id: org_id
    } do
      product = product_fixture(%{organization_id: org_id})

      _pending =
        batch_fixture(%{
          organization_id: org_id,
          site_id: lab_site.id,
          product_id: product.id,
          batch_no: "LAB-PENDING-001",
          pending: true
        })

      {:ok, _lv, html} = live(log_in_user(conn, lab_tech), ~p"/lab/receive-stock")

      assert html =~ "LAB-PENDING-001"
    end

    test "View shows batch detail panel, Approve receipt marks batch active", %{
      conn: conn,
      lab_tech: lab_tech,
      lab_site: lab_site,
      org_id: org_id
    } do
      product = product_fixture(%{organization_id: org_id, generic_name: "Lab Reagent X"})

      pending =
        batch_fixture(%{
          organization_id: org_id,
          site_id: lab_site.id,
          product_id: product.id,
          batch_no: "LAB-PENDING-002",
          pending: true
        })

      {:ok, lv, _html} = live(log_in_user(conn, lab_tech), ~p"/lab/receive-stock")

      # Click View — detail panel appears
      lv
      |> element("[phx-click='view_batch'][phx-value-id='#{pending.id}']")
      |> render_click()

      html = render(lv)
      assert html =~ "Review batch before receiving"
      assert html =~ "LAB-PENDING-002"
      assert html =~ "Lab Reagent X"

      # Click Approve receipt — batch is activated
      lv
      |> element("[phx-click='receive_batch'][phx-value-id='#{pending.id}']")
      |> render_click()

      assert render(lv) =~ "Batch received and marked active."
      refute has_element?(lv, "#batch-review-panel")

      updated = ThamaniDawa.Batches.get_batch!(org_id, pending.id)
      assert updated.approver_id == lab_tech.id
      assert updated.received_at != nil
    end

    test "admin sees pending batches across all lab-capable sites but not pharmacy-only sites", %{
      conn: conn,
      admin: admin,
      lab_site: lab_site,
      pharmacy_site: pharmacy_site,
      org_id: org_id
    } do
      product = product_fixture(%{organization_id: org_id})

      _lab_pending =
        batch_fixture(%{
          organization_id: org_id,
          site_id: lab_site.id,
          product_id: product.id,
          batch_no: "LAB-ADMIN-PENDING",
          pending: true
        })

      _pharm_pending =
        batch_fixture(%{
          organization_id: org_id,
          site_id: pharmacy_site.id,
          product_id: product.id,
          batch_no: "PHARM-ADMIN-PENDING",
          pending: true
        })

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/lab/receive-stock")

      assert html =~ "LAB-ADMIN-PENDING"
      refute html =~ "PHARM-ADMIN-PENDING"
    end

    test "pending table shows serial, manufacture date, and supplier when present", %{
      conn: conn,
      lab_tech: lab_tech,
      lab_site: lab_site,
      org_id: org_id
    } do
      product = product_fixture(%{organization_id: org_id})
      supplier = supplier_fixture(%{organization_id: org_id, name: "Reagent Supply Co"})

      _pending =
        batch_fixture(%{
          organization_id: org_id,
          site_id: lab_site.id,
          product_id: product.id,
          batch_no: "LAB-TRACE-001",
          serial: "SN-99887",
          manufacture_date: ~D[2026-02-01],
          supplier_id: supplier.id,
          pending: true
        })

      {:ok, _lv, html} = live(log_in_user(conn, lab_tech), ~p"/lab/receive-stock")

      assert html =~ "SN-99887"
      assert html =~ "2026-02-01"
      assert html =~ "Reagent Supply Co"
    end

    test "pending table shows a dash for serial, manufacture date, and supplier when absent", %{
      conn: conn,
      lab_tech: lab_tech,
      lab_site: lab_site,
      org_id: org_id
    } do
      product = product_fixture(%{organization_id: org_id})

      batch_fixture(%{
        organization_id: org_id,
        site_id: lab_site.id,
        product_id: product.id,
        batch_no: "LAB-BARE-001",
        pending: true
      })

      {:ok, lv, _html} = live(log_in_user(conn, lab_tech), ~p"/lab/receive-stock")

      assert has_element?(lv, "#pending-batches td", "—")
    end

    test "review panel shows the serial when present", %{
      conn: conn,
      lab_tech: lab_tech,
      lab_site: lab_site,
      org_id: org_id
    } do
      product = product_fixture(%{organization_id: org_id})

      pending =
        batch_fixture(%{
          organization_id: org_id,
          site_id: lab_site.id,
          product_id: product.id,
          batch_no: "LAB-PANEL-SERIAL",
          serial: "SN-PANEL-1",
          pending: true
        })

      {:ok, lv, _html} = live(log_in_user(conn, lab_tech), ~p"/lab/receive-stock")

      lv
      |> element("[phx-click='view_batch'][phx-value-id='#{pending.id}']")
      |> render_click()

      assert render(lv) =~ "SN-PANEL-1"
    end
  end

  describe "walk-in form" do
    test "site dropdown excludes pharmacy-only sites", %{
      conn: conn,
      admin: admin,
      lab_site: lab_site,
      pharmacy_site: pharmacy_site
    } do
      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/lab/receive-stock")

      assert html =~ "value=\"#{lab_site.id}\""
      refute html =~ "value=\"#{pharmacy_site.id}\""
    end

    test "submitting with a pharmacy-only site_id is rejected server-side", %{
      conn: conn,
      lab_tech: lab_tech,
      pharmacy_site: pharmacy_site,
      org_id: org_id
    } do
      # For a lab tech, site_id is a hidden input (site_locked: true) — no option
      # validation in the test framework. This simulates a crafted POST that
      # overrides the hidden field to target a pharmacy-only site.
      product = product_fixture(%{organization_id: org_id})

      {:ok, lv, _html} = live(log_in_user(conn, lab_tech), ~p"/lab/receive-stock")

      # Use element/2 (not form/3) to bypass LiveViewTest's option-value
      # validation so we can simulate a crafted POST with an invalid site_id.
      lv
      |> element("form[phx-submit='save']")
      |> render_submit(%{
        "batch" => %{
          "product_id" => to_string(product.id),
          "site_id" => to_string(pharmacy_site.id),
          "gtin" => unique_gtin(),
          "batch_no" => "WRONG-SITE-001",
          "expiry_date" => "2027-06-01",
          "quantity" => "10"
        }
      })

      assert render(lv) =~ "Selected site cannot receive lab consumables."
    end

    test "walk-in save creates and immediately receives the batch", %{
      conn: conn,
      lab_tech: lab_tech,
      lab_site: lab_site,
      org_id: org_id
    } do
      product = product_fixture(%{organization_id: org_id})
      gtin = unique_gtin()

      {:ok, lv, _html} = live(log_in_user(conn, lab_tech), ~p"/lab/receive-stock")

      lv
      |> form("form[phx-submit='save']",
        batch: %{
          product_id: product.id,
          site_id: lab_site.id,
          gtin: gtin,
          batch_no: "WALKIN-001",
          expiry_date: "2027-06-01",
          quantity: 50
        }
      )
      |> render_submit()

      assert_redirect(lv, ~p"/lab")
    end
  end
end
