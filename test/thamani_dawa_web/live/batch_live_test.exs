defmodule ThamaniDawaWeb.BatchLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.PatientsFixtures
  import ThamaniDawa.PatientVisitsFixtures
  import ThamaniDawa.PrescriptionsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures

  alias ThamaniDawa.Prescriptions

  setup do
    admin = user_fixture()
    {:ok, admin: admin}
  end

  describe "show" do
    test "renders batch identity details", %{conn: conn, admin: admin} do
      site = site_fixture(%{organization_id: admin.organization_id})
      product = product_fixture(%{organization_id: admin.organization_id})

      batch =
        batch_fixture(%{
          organization_id: admin.organization_id,
          site_id: site.id,
          product_id: product.id,
          batch_no: "TRACE-BATCH-1"
        })

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/batches/#{batch.id}")

      assert html =~ "TRACE-BATCH-1"
      assert html =~ site.name
    end

    test "shows the receiving event and a prescription dispense in the timeline", %{
      conn: conn,
      admin: admin
    } do
      site = site_fixture(%{organization_id: admin.organization_id})
      product = product_fixture(%{organization_id: admin.organization_id})
      patient = patient_fixture(%{organization_id: admin.organization_id})

      patient_visit =
        patient_visit_fixture(%{
          organization_id: admin.organization_id,
          site_id: site.id,
          patient_id: patient.id
        })

      prescription =
        prescription_fixture(%{
          organization_id: admin.organization_id,
          patient_visit_id: patient_visit.id
        })

      item =
        prescription_item_fixture(%{
          organization_id: admin.organization_id,
          prescription_id: prescription.id,
          product_id: product.id,
          quantity_prescribed: 5
        })

      batch =
        batch_fixture(%{
          organization_id: admin.organization_id,
          site_id: site.id,
          product_id: product.id,
          batch_no: "TRACE-BATCH-2",
          quantity: 20,
          remaining_quantity: 20
        })

      assert {:ok, _updated_item} =
               Prescriptions.dispense_item(admin.organization_id, item.id, admin.id, 5)

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/batches/#{batch.id}")

      assert html =~ "Received"
      assert html =~ "Dispensed 5 units"
      assert html =~ "Rx ##{prescription.id}"
      assert html =~ patient.full_name
    end
  end

  describe "product and site pages" do
    test "product page's batch row links to the batch detail page", %{conn: conn, admin: admin} do
      product = product_fixture(%{organization_id: admin.organization_id})

      batch =
        batch_fixture(%{organization_id: admin.organization_id, product_id: product.id})

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/products/#{product.id}")

      assert html =~ ~p"/org/batches/#{batch.id}"
    end

    test "site page's near-expiry batch row links to the batch detail page", %{
      conn: conn,
      admin: admin
    } do
      site = site_fixture(%{organization_id: admin.organization_id, site_type: :pharmacy})
      product = product_fixture(%{organization_id: admin.organization_id})

      batch =
        batch_fixture(%{
          organization_id: admin.organization_id,
          site_id: site.id,
          product_id: product.id,
          expiry_date: Date.add(Date.utc_today(), 5)
        })

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/sites/#{site.id}")

      assert html =~ ~p"/org/batches/#{batch.id}"
    end
  end
end
