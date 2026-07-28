defmodule ThamaniDawaWeb.SiteLive.ShowTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.LabOrdersFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.PatientVisitsFixtures
  import ThamaniDawa.PrescriptionsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures

  alias ThamaniDawa.PatientVisits.PatientVisit
  alias ThamaniDawa.Repo

  defp stat_value(html, label) do
    [_, value] = Regex.run(~r/#{Regex.escape(label)}.*?dashboard-stat-tile-value">(\d+)</s, html)
    value
  end

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

  describe "site stats" do
    test "shows patient visit, prescription, and lab order counts scoped to this site", %{
      conn: conn
    } do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id, site_type: :pharmacy_lab})
      other_site = site_fixture(%{organization_id: organization.id, site_type: :pharmacy_lab})

      visit = patient_visit_fixture(%{organization_id: organization.id, site_id: site.id})
      prescription_fixture(%{organization_id: organization.id, patient_visit_id: visit.id})

      lab_order_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        patient_visit_id: visit.id,
        status: :completed
      })

      other_visit =
        patient_visit_fixture(%{organization_id: organization.id, site_id: other_site.id})

      prescription_fixture(%{organization_id: organization.id, patient_visit_id: other_visit.id})

      lab_order_fixture(%{
        organization_id: organization.id,
        site_id: other_site.id,
        patient_visit_id: other_visit.id,
        status: :completed
      })

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/sites/#{site.id}")

      assert stat_value(html, "Patient visits") == "1"
      assert stat_value(html, "Prescriptions") == "1"
      assert stat_value(html, "Lab orders completed") == "1"
    end

    test "shows only staff assigned to this site", %{conn: conn} do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})
      other_site = site_fixture(%{organization_id: organization.id})

      staff_fixture(%{organization_id: organization.id, site_id: site.id, name: "Site Nurse"})

      staff_fixture(%{
        organization_id: organization.id,
        site_id: other_site.id,
        name: "Other Site Nurse"
      })

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/sites/#{site.id}")

      assert html =~ "Site Nurse"
      refute html =~ "Other Site Nurse"
      assert stat_value(html, "Staff assigned") == "1"
    end

    test "clicking a range pill re-renders without error", %{conn: conn} do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/sites/#{site.id}")

      html = lv |> element("button", "This Week") |> render_click()
      assert html =~ "Patient visits"
    end

    test "clicking Custom reveals a date-range form, and submitting it recomputes stats", %{
      conn: conn
    } do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      visit = patient_visit_fixture(%{organization_id: organization.id, site_id: site.id})

      from(v in PatientVisit, where: v.id == ^visit.id)
      |> Repo.update_all(set: [inserted_at: DateTime.add(DateTime.utc_now(), -8, :day)])

      {:ok, lv, html} = live(log_in_user(conn, admin), ~p"/org/sites/#{site.id}")
      refute html =~ "site-custom-range-form"
      assert stat_value(html, "Patient visits") == "0"

      html = lv |> element("button", "Custom") |> render_click()
      assert html =~ "site-custom-range-form"

      from = Date.utc_today() |> Date.add(-10) |> Date.to_iso8601()
      to = Date.utc_today() |> Date.to_iso8601()

      html = render_submit(lv, "apply_custom_range", %{"from" => from, "to" => to})
      assert stat_value(html, "Patient visits") == "1"
    end

    test "an invalid custom range shows a flash error and does not crash", %{conn: conn} do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/sites/#{site.id}")

      lv |> element("button", "Custom") |> render_click()

      html =
        render_submit(lv, "apply_custom_range", %{"from" => "not-a-date", "to" => "also-not"})

      assert html =~ "Enter a valid from and to date"
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
