defmodule ThamaniDawaWeb.SiteLive.ShowTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.LabOrdersFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.PrescriptionsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures

  describe "pharmacy-only site" do
    test "shows near-expiry stock and pending prescriptions scoped to this site, no tab toggle",
         %{conn: conn} do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id, site_type: :pharmacy})
      other_site = site_fixture(%{organization_id: organization.id, site_type: :pharmacy})
      product = product_fixture(%{organization_id: organization.id})

      near_batch =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          product_id: product.id,
          batch_no: "AT-THIS-SITE",
          expiry_date: Date.add(Date.utc_today(), 10)
        })

      _elsewhere_batch =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: other_site.id,
          product_id: product.id,
          batch_no: "AT-OTHER-SITE",
          expiry_date: Date.add(Date.utc_today(), 10)
        })

      visit =
        ThamaniDawa.PatientVisitsFixtures.patient_visit_fixture(%{
          organization_id: organization.id,
          site_id: site.id
        })

      prescription =
        prescription_fixture(%{organization_id: organization.id, patient_visit_id: visit.id})

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/sites/#{site.id}")

      assert html =~ "AT-THIS-SITE"
      refute html =~ "AT-OTHER-SITE"
      assert html =~ "#{prescription.total_amount}"
      refute html =~ "tabs-boxed"

      assert near_batch.site_id == site.id
    end

    test "shows a product at or below its reorder level in the low-stock table", %{conn: conn} do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id, site_type: :pharmacy})

      product =
        product_fixture(%{
          organization_id: organization.id,
          generic_name: "Low Stock Drug",
          reorder_level: 10
        })

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        quantity: 5,
        remaining_quantity: 5,
        expiry_date: Date.add(Date.utc_today(), 300)
      })

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/sites/#{site.id}")

      assert html =~ "Low Stock Drug"
    end

    test "?tab=lab on a pharmacy-only site falls back to the pharmacy tab", %{conn: conn} do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id, site_type: :pharmacy})

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/sites/#{site.id}?tab=lab")

      assert html =~ "Low stock"
      refute html =~ "Pending orders"
    end
  end

  describe "lab-only site" do
    test "shows pending lab orders scoped to this site, no tab toggle", %{conn: conn} do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id, site_type: :lab})

      lab_order = lab_order_fixture(%{organization_id: organization.id, site_id: site.id})

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/sites/#{site.id}")

      assert html =~ "Pending orders"
      assert html =~ Phoenix.Naming.humanize(lab_order.status)
      refute html =~ "tabs-boxed"
    end

    test "?tab=pharmacy on a lab-only site falls back to the lab tab", %{conn: conn} do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id, site_type: :lab})

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/sites/#{site.id}?tab=pharmacy")

      assert html =~ "Pending orders"
      refute html =~ "Low stock"
    end
  end

  describe "warehouse-only site" do
    test "shows neither pharmacy nor lab operations, and does not crash", %{conn: conn} do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id, site_type: :warehouse})

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/sites/#{site.id}")

      assert html =~ "no pharmacy or lab operations"
      refute html =~ "Low stock"
      refute html =~ "Pending orders"
    end
  end

  describe "pharmacy_lab site" do
    test "shows a tab toggle defaulting to pharmacy, and switches to lab via ?tab=lab", %{
      conn: conn
    } do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id, site_type: :pharmacy_lab})

      {:ok, lv, html} = live(log_in_user(conn, admin), ~p"/org/sites/#{site.id}")

      assert html =~ "tabs-boxed"
      assert html =~ "Low stock"

      html = lv |> element("a", "Lab") |> render_click()
      assert html =~ "Pending orders"
    end
  end

  describe "SiteLive.Index" do
    test "clicking a site row navigates to its show page", %{conn: conn} do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/sites")

      assert {:error, {:live_redirect, %{to: to}}} =
               lv |> element("#sites td", site.name) |> render_click()

      assert to == ~p"/org/sites/#{site.id}"
    end
  end
end
