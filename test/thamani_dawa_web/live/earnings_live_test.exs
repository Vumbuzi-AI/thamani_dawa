defmodule ThamaniDawaWeb.EarningsLiveTest do
  @moduledoc """
  Covers the acceptance criteria for the organization transactions page:
  organization-scoped transaction history, date/site/method/status filters
  that reconcile exactly with the visible transaction rows, empty states, and
  cross-organization isolation. Route-level access control is covered
  generically by `AdminRoutesTest`.
  """

  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.LabOrdersFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.PaymentsFixtures
  import ThamaniDawa.PrescriptionsFixtures
  import ThamaniDawa.SitesFixtures

  alias ThamaniDawa.Payments
  alias ThamaniDawa.Payments.Payment
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sales.Sale

  describe "totals" do
    test "shows the empty ledger and site filter for a multi-site organization with no payments",
         %{conn: conn} do
      admin = user_fixture()
      site_fixture(%{organization_id: admin.organization_id, name: "Branch A"})
      site_fixture(%{organization_id: admin.organization_id, name: "Branch B"})

      {:ok, lv, html} = live(log_in_user(conn, admin), ~p"/org/earnings")

      assert html =~ "No transactions yet"
      assert has_element?(lv, "#earnings-chip-site", "Site")
      assert has_element?(lv, "th", "Site")
    end

    test "hides the site filter/column for a single-site organization", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id, name: "Only Branch"})

      lab_order =
        lab_order_fixture(%{organization_id: admin.organization_id, site_id: site.id})

      payment_fixture(%{
        organization_id: admin.organization_id,
        lab_order_id: lab_order.id,
        amount: Decimal.new("500")
      })

      {:ok, lv, html} = live(log_in_user(conn, admin), ~p"/org/earnings")

      assert html =~ "KSh 500"
      refute has_element?(lv, "th", "Site")
      refute has_element?(lv, "select[name='filters[site]']")
    end

    test "lists completed, pending, and failed payments from this organization", %{conn: conn} do
      admin = user_fixture()
      site_a = site_fixture(%{organization_id: admin.organization_id, name: "Branch A"})
      site_b = site_fixture(%{organization_id: admin.organization_id, name: "Branch B"})

      lab_order_a =
        lab_order_fixture(%{organization_id: admin.organization_id, site_id: site_a.id})

      lab_order_b =
        lab_order_fixture(%{organization_id: admin.organization_id, site_id: site_b.id})

      completed_a =
        payment_fixture(%{
          organization_id: admin.organization_id,
          lab_order_id: lab_order_a.id,
          amount: Decimal.new("1000")
        })

      completed_b =
        payment_fixture(%{
          organization_id: admin.organization_id,
          lab_order_id: lab_order_b.id,
          amount: Decimal.new("250")
        })

      pending =
        payment_fixture(%{
          organization_id: admin.organization_id,
          lab_order_id:
            lab_order_fixture(%{organization_id: admin.organization_id, site_id: site_a.id}).id,
          amount: Decimal.new("9999")
        })

      failed =
        payment_fixture(%{
          organization_id: admin.organization_id,
          lab_order_id:
            lab_order_fixture(%{organization_id: admin.organization_id, site_id: site_a.id}).id,
          amount: Decimal.new("8888")
        })

      {:ok, _} = Payments.complete_payment(completed_a)
      {:ok, _} = Payments.complete_payment(completed_b)
      {:ok, _} = Payments.fail_payment(failed, "declined")

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/earnings")

      assert has_element?(lv, "#transactions-#{completed_a.id}")
      assert has_element?(lv, "#transactions-#{completed_b.id}")
      assert has_element?(lv, "#transactions-#{pending.id}")
      assert has_element?(lv, "#transactions-#{failed.id}")
    end

    test "does not include another organization's transactions", %{conn: conn} do
      admin = user_fixture()
      other_org = organization_fixture()

      payment = payment_fixture(%{organization_id: other_org.id, amount: Decimal.new("5000")})
      {:ok, _} = Payments.complete_payment(payment)

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/earnings")

      refute html =~ "KSh 5,000"
      assert html =~ "No transactions yet"
    end
  end

  describe "transaction history" do
    test "lists a transaction linking back to its originating lab order", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id})
      lab_order = lab_order_fixture(%{organization_id: admin.organization_id, site_id: site.id})

      payment_fixture(%{
        organization_id: admin.organization_id,
        lab_order_id: lab_order.id,
        amount: Decimal.new("400"),
        payment_type: "Cash"
      })

      {:ok, lv, html} = live(log_in_user(conn, admin), ~p"/org/earnings")

      assert html =~ "KSh 400"
      assert html =~ "Cash"

      assert has_element?(
               lv,
               "a[href='/lab/orders/#{lab_order.id}']",
               "Lab order ##{lab_order.id}"
             )
    end

    test "lists a transaction linking back to its originating prescription", %{conn: conn} do
      admin = user_fixture()
      prescription = prescription_fixture(%{organization_id: admin.organization_id})

      payment_fixture(%{
        organization_id: admin.organization_id,
        prescription_id: prescription.id,
        amount: Decimal.new("300")
      })

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/earnings")

      assert has_element?(
               lv,
               "a[href='/pharmacy/prescriptions/#{prescription.id}']",
               "Prescription ##{prescription.id}"
             )
    end

    test "lists a quick-sale payment without requiring an unavailable detail route", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id})

      sale =
        %Sale{}
        |> Sale.changeset(%{site_id: site.id, total_amount: Decimal.new("125")})
        |> Ecto.Changeset.put_change(:organization_id, admin.organization_id)
        |> Repo.insert!()

      assert {:ok, %Payment{} = payment} =
               Payments.create_payment(admin.organization_id, %{
                 sale_id: sale.id,
                 amount: sale.total_amount,
                 payment_type: "Cash"
               })

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/earnings")

      assert has_element?(lv, "#transactions-#{payment.id}", "Quick sale ##{sale.id}")
      refute has_element?(lv, "#transactions-#{payment.id} a", "Quick sale ##{sale.id}")
    end

    test "shows the empty state when the organization has no payments", %{conn: conn} do
      admin = user_fixture()

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/earnings")

      assert html =~ "No transactions yet"
    end

    test "does not include another organization's transactions", %{conn: conn} do
      admin = user_fixture()
      other_org = organization_fixture()

      payment_fixture(%{organization_id: other_org.id})

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/earnings")

      assert html =~ "No transactions yet"
    end
  end

  describe "filters" do
    setup %{conn: conn} do
      admin = user_fixture()
      site_a = site_fixture(%{organization_id: admin.organization_id, name: "Branch A"})
      site_b = site_fixture(%{organization_id: admin.organization_id, name: "Branch B"})

      lab_order_a =
        lab_order_fixture(%{organization_id: admin.organization_id, site_id: site_a.id})

      lab_order_b =
        lab_order_fixture(%{organization_id: admin.organization_id, site_id: site_b.id})

      cash_payment =
        payment_fixture(%{
          organization_id: admin.organization_id,
          lab_order_id: lab_order_a.id,
          amount: Decimal.new("111"),
          payment_type: "Cash"
        })

      {:ok, completed_cash} = Payments.complete_payment(cash_payment)

      mobile_payment =
        payment_fixture(%{
          organization_id: admin.organization_id,
          lab_order_id: lab_order_b.id,
          amount: Decimal.new("222"),
          payment_type: "Mobile Money"
        })

      {:ok, failed_mobile} = Payments.fail_payment(mobile_payment, "declined")

      %{
        conn: log_in_user(conn, admin),
        site_a: site_a,
        site_b: site_b,
        completed_cash: completed_cash,
        failed_mobile: failed_mobile
      }
    end

    test "filtering by site shows only that site's transactions", %{
      conn: conn,
      site_a: site_a,
      completed_cash: completed_cash,
      failed_mobile: failed_mobile
    } do
      {:ok, lv, _html} = live(conn, ~p"/org/earnings")

      render_click(lv, "set_filter", %{"field" => "site", "value" => to_string(site_a.id)})

      assert has_element?(lv, "#transactions-#{completed_cash.id}")
      refute has_element?(lv, "#transactions-#{failed_mobile.id}")
    end

    test "filtering by method shows only that method's transactions", %{
      conn: conn,
      completed_cash: completed_cash,
      failed_mobile: failed_mobile
    } do
      {:ok, lv, _html} = live(conn, ~p"/org/earnings")

      render_click(lv, "set_filter", %{"field" => "method", "value" => "Mobile Money"})

      assert has_element?(lv, "#transactions-#{failed_mobile.id}")
      refute has_element?(lv, "#transactions-#{completed_cash.id}")
    end

    test "searching transactions filters the ledger from the toolbar", %{
      conn: conn,
      completed_cash: completed_cash,
      failed_mobile: failed_mobile
    } do
      {:ok, lv, _html} = live(conn, ~p"/org/earnings")

      lv
      |> form("#transaction-search-form", %{search: "Mobile Money"})
      |> render_change()

      assert has_element?(lv, "#transactions-#{failed_mobile.id}")
      refute has_element?(lv, "#transactions-#{completed_cash.id}")
    end

    test "filtering by status shows only that status's transactions", %{
      conn: conn,
      completed_cash: completed_cash,
      failed_mobile: failed_mobile
    } do
      {:ok, lv, _html} = live(conn, ~p"/org/earnings")

      render_click(lv, "set_filter", %{"field" => "status", "value" => "failed"})

      assert has_element?(lv, "#transactions-#{failed_mobile.id}")
      refute has_element?(lv, "#transactions-#{completed_cash.id}")
    end

    test "filtering by a date range excludes transactions outside it", %{
      conn: conn,
      completed_cash: completed_cash,
      failed_mobile: failed_mobile
    } do
      completed_cash
      |> Ecto.Changeset.change(
        inserted_at: DateTime.utc_now() |> DateTime.add(-10, :day) |> DateTime.truncate(:second)
      )
      |> ThamaniDawa.Repo.update!()

      {:ok, lv, _html} = live(conn, ~p"/org/earnings")

      today = Date.utc_today() |> Date.to_iso8601()

      lv
      |> form("#earnings-date-form", %{date_from: today, date_to: today})
      |> render_submit()

      assert has_element?(lv, "#transactions-#{failed_mobile.id}")
      refute has_element?(lv, "#transactions-#{completed_cash.id}")
    end

    test "clearing filters restores every transaction", %{
      conn: conn,
      site_a: site_a,
      completed_cash: completed_cash,
      failed_mobile: failed_mobile
    } do
      {:ok, lv, _html} = live(conn, ~p"/org/earnings")

      render_click(lv, "set_filter", %{"field" => "site", "value" => to_string(site_a.id)})

      refute has_element?(lv, "#transactions-#{failed_mobile.id}")

      render_click(lv, "set_filter", %{"field" => "site", "value" => ""})

      assert has_element?(lv, "#transactions-#{completed_cash.id}")
      assert has_element?(lv, "#transactions-#{failed_mobile.id}")
    end

    test "combining filters that match nothing shows the filtered empty state", %{
      conn: conn,
      site_a: site_a
    } do
      {:ok, lv, _html} = live(conn, ~p"/org/earnings")

      render_click(lv, "set_filter", %{"field" => "site", "value" => to_string(site_a.id)})
      render_click(lv, "set_filter", %{"field" => "status", "value" => "failed"})

      assert render(lv) =~ "No transactions match your filters"
    end

    test "removing a single filter chip clears just that filter", %{
      conn: conn,
      site_a: site_a,
      completed_cash: completed_cash,
      failed_mobile: failed_mobile
    } do
      {:ok, lv, _html} = live(conn, ~p"/org/earnings")

      render_click(lv, "set_filter", %{"field" => "site", "value" => to_string(site_a.id)})

      refute has_element?(lv, "#transactions-#{failed_mobile.id}")

      render_click(lv, "set_filter", %{"field" => "site", "value" => ""})

      assert has_element?(lv, "#transactions-#{completed_cash.id}")
      assert has_element?(lv, "#transactions-#{failed_mobile.id}")
    end

    test "an unparseable date filter is ignored rather than raising", %{
      conn: conn,
      completed_cash: completed_cash,
      failed_mobile: failed_mobile
    } do
      {:ok, lv, _html} = live(conn, ~p"/org/earnings")

      html = render_submit(lv, "apply_date_range", %{"date_from" => "not-a-date"})

      assert html =~ "Any time"
      assert has_element?(lv, "#transactions-#{completed_cash.id}")
      assert has_element?(lv, "#transactions-#{failed_mobile.id}")
    end

    test "a stale site id in the filter falls back to showing the raw value in its chip", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/org/earnings")

      html = render_click(lv, "set_filter", %{"field" => "site", "value" => "999999"})

      assert html =~ "999999"
    end
  end
end
