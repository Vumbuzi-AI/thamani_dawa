defmodule ThamaniDawaWeb.PharmacyDashboardLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures

  defp pharmacist_at(organization, site) do
    staff_fixture(%{organization_id: organization.id, site_id: site.id})
  end

  describe "stock alerts" do
    test "a pending (unreceived) batch is excluded from low-stock and near-expiry, but counted as a pending receipt",
         %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at(organization, site)

      product =
        product_fixture(%{
          organization_id: organization.id,
          generic_name: "Pending Only Drug",
          reorder_level: 100
        })

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        quantity: 5,
        remaining_quantity: 5,
        expiry_date: Date.add(Date.utc_today(), 10),
        pending: true
      })

      {:ok, lv, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy")

      # Would trivially qualify for low-stock/near-expiry if pending batches
      # weren't excluded (reorder_level 100 > quantity 5, expiry in 10 days).
      refute has_element?(lv, "#low-stock", "Pending Only Drug")
      refute has_element?(lv, "#near-expiry", "Pending Only Drug")
      refute has_element?(lv, "#out-of-stock", "Pending Only Drug")
      assert html =~ "awaiting receipt at your site"
    end

    test "distinguishes out-of-stock from low-stock", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at(organization, site)

      out_of_stock_product =
        product_fixture(%{
          organization_id: organization.id,
          generic_name: "Zero Stock Drug",
          reorder_level: 10
        })

      low_stock_product =
        product_fixture(%{
          organization_id: organization.id,
          generic_name: "Low Stock Drug",
          reorder_level: 10
        })

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: out_of_stock_product.id,
        quantity: 5,
        remaining_quantity: 0
      })

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: low_stock_product.id,
        quantity: 5,
        remaining_quantity: 5
      })

      {:ok, lv, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy")

      assert html =~ "Zero Stock Drug"
      assert html =~ "Low Stock Drug"
      assert has_element?(lv, "#out-of-stock", "Zero Stock Drug")
      refute has_element?(lv, "#out-of-stock", "Low Stock Drug")
      assert has_element?(lv, "#low-stock", "Low Stock Drug")
      refute has_element?(lv, "#low-stock", "Zero Stock Drug")
    end

    test "low-stock and out-of-stock rows navigate to receive-stock", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at(organization, site)
      product = product_fixture(%{organization_id: organization.id, reorder_level: 10})

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        quantity: 5,
        remaining_quantity: 0
      })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy")

      assert {:error, {:live_redirect, %{to: to}}} =
               lv |> element("#out-of-stock td", product.generic_name) |> render_click()

      assert to == ~p"/pharmacy/receive-stock"
    end

    test "near-expiry rows navigate to scan lookup pre-filled with the batch's gtin", %{
      conn: conn
    } do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at(organization, site)
      gtin = unique_gtin()
      product = product_fixture(%{organization_id: organization.id, gtin: gtin})

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        gtin: gtin,
        batch_no: "LOT-NEAR-EXPIRY",
        expiry_date: Date.add(Date.utc_today(), 10)
      })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy")

      assert {:error, {:live_redirect, %{to: to}}} =
               lv |> element("#near-expiry td", "LOT-NEAR-EXPIRY") |> render_click()

      assert to == ~p"/pharmacy/scan?gtin=#{gtin}"
    end

    test "healthy stock (above reorder level) appears in neither out-of-stock nor low-stock",
         %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at(organization, site)

      product =
        product_fixture(%{
          organization_id: organization.id,
          generic_name: "Healthy Stock Drug",
          reorder_level: 10
        })

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        quantity: 100,
        remaining_quantity: 100
      })

      {:ok, lv, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy")

      refute html =~ "Healthy Stock Drug"
      refute has_element?(lv, "#out-of-stock", "Healthy Stock Drug")
      refute has_element?(lv, "#low-stock", "Healthy Stock Drug")
    end
  end

  describe "pending prescriptions" do
    test "lists only pending and partially-dispensed prescriptions at this site", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at(organization, site)
      patient = ThamaniDawa.PatientsFixtures.patient_fixture(%{organization_id: organization.id})

      patient_visit =
        ThamaniDawa.PatientVisitsFixtures.patient_visit_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          patient_id: patient.id
        })

      pending =
        ThamaniDawa.PrescriptionsFixtures.prescription_fixture(%{
          organization_id: organization.id,
          patient_visit_id: patient_visit.id,
          status: :pending,
          has_paid: false
        })

      _completed =
        ThamaniDawa.PrescriptionsFixtures.prescription_fixture(%{
          organization_id: organization.id,
          patient_visit_id: patient_visit.id,
          status: :completed
        })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy")

      assert has_element?(lv, "#pending-prescriptions", "Pending")
      assert has_element?(lv, "#pending-prescriptions", "No")

      assert {:error, {:live_redirect, %{to: to}}} =
               lv |> element("#pending-prescriptions td", "Pending") |> render_click()

      assert to == ~p"/pharmacy/prescriptions/#{pending.id}"
    end
  end

  describe "pending receipts banner" do
    test "shows a count and link when batches are awaiting receipt at this site", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at(organization, site)
      product = product_fixture(%{organization_id: organization.id})

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        pending: true
      })

      {:ok, lv, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy")

      assert html =~ "awaiting receipt at your site"
      assert has_element?(lv, "a[href='/pharmacy/receive-stock']", "Receive stock")
    end

    test "shows nothing when there are no pending batches", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at(organization, site)

      {:ok, _lv, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy")

      refute html =~ "awaiting receipt at your site"
    end
  end
end
