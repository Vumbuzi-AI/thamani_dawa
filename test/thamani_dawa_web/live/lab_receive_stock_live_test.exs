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

    test "Receive link opens modal, approving receipt marks batch active", %{
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

      {:ok, lv, _html} =
        live(log_in_user(conn, lab_tech), ~p"/lab/receive-stock/#{pending.id}/receive")

      html = render(lv)
      assert html =~ "Receive batch"
      assert html =~ "LAB-PENDING-002"
      assert html =~ "Lab Reagent X"

      lv
      |> form("#receive-batch-form", %{})
      |> render_submit()

      assert_patch(lv, ~p"/lab/receive-stock")
      assert render(lv) =~ "Batch received and marked active."

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

    test "receive modal shows the serial when present", %{
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

      {:ok, lv, _html} =
        live(log_in_user(conn, lab_tech), ~p"/lab/receive-stock/#{pending.id}/receive")

      assert render(lv) =~ "SN-PANEL-1"
    end
  end
end
