defmodule ThamaniDawaWeb.PharmacyStockTakeLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.SitesFixtures
  import ThamaniDawa.StockTakesFixtures

  alias ThamaniDawa.Batches
  alias ThamaniDawa.StockTakes

  describe "access control" do
    test "an admin can reach it", %{conn: conn} do
      admin = user_fixture()
      assert {:ok, _view, _html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock-take")
    end

    test "a pharmacist can reach it", %{conn: conn} do
      pharmacist = staff_fixture(%{role: :pharmacist})
      assert {:ok, _view, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock-take")
    end

    test "combined pharmacy/lab staff can reach it", %{conn: conn} do
      pharma_lab = staff_fixture(%{role: :pharma_lab})
      assert {:ok, _view, _html} = live(log_in_user(conn, pharma_lab), ~p"/pharmacy/stock-take")
    end

    test "a lab technician is redirected away", %{conn: conn} do
      lab_technician = staff_fixture(%{role: :lab_technician})

      assert {:error, {:redirect, %{to: "/"}}} =
               live(log_in_user(conn, lab_technician), ~p"/pharmacy/stock-take")
    end

    test "an anonymous visitor is redirected away", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/pharmacy/stock-take")
    end
  end

  describe "starting a stock take" do
    test "a site-locked pharmacist starts one at their own site via the modal", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id, name: "Main Pharmacy"})

      pharmacist =
        staff_fixture(%{
          organization_id: admin.organization_id,
          invited_by_id: admin.id,
          role: :pharmacist,
          site_id: site.id
        })

      batch_fixture(%{organization_id: admin.organization_id, site_id: site.id, quantity: 20})

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock-take")

      lv |> element("button", "+ Start a stock take") |> render_click()
      assert has_element?(lv, "#start-stock-take-modal")
      assert render(lv) =~ "Main Pharmacy"

      lv
      |> form("#start-stock-take-form", stock_take: %{notes: "Monthly count"})
      |> render_submit()

      assert_redirect(lv)

      assert %StockTakes.StockTake{status: :draft} =
               StockTakes.get_active_stock_take(admin.organization_id, site.id)
    end

    test "shows a dash when a site-locked staff member's home site isn't pharmacy-capable", %{
      conn: conn
    } do
      admin = user_fixture()
      lab_only_site = site_fixture(%{organization_id: admin.organization_id, site_type: :lab})

      pharmacist =
        staff_fixture(%{
          organization_id: admin.organization_id,
          invited_by_id: admin.id,
          role: :pharmacist,
          site_id: lab_only_site.id
        })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock-take")

      lv |> element("button", "+ Start a stock take") |> render_click()
      assert render(lv) =~ "—"
    end

    test "an admin must choose a site from the select", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id, name: "Branch A"})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock-take")

      lv |> element("button", "+ Start a stock take") |> render_click()

      lv
      |> form("#start-stock-take-form", stock_take: %{site_id: to_string(site.id)})
      |> render_submit()

      assert_redirect(lv)
      assert StockTakes.get_active_stock_take(admin.organization_id, site.id)
    end

    test "shows an error instead of starting a second draft at the same site", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id})
      stock_take_fixture(%{organization_id: admin.organization_id, site_id: site.id})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock-take")

      lv |> element("button", "+ Start a stock take") |> render_click()

      html =
        lv
        |> form("#start-stock-take-form", stock_take: %{site_id: to_string(site.id)})
        |> render_submit()

      assert html =~ "already has a stock take in progress"
    end

    test "cancel closes the start modal without starting anything", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock-take")

      lv |> element("button", "+ Start a stock take") |> render_click()
      assert has_element?(lv, "#start-stock-take-modal")

      lv |> element("button", "Cancel") |> render_click()
      refute has_element?(lv, "#start-stock-take-modal")
      refute StockTakes.get_active_stock_take(admin.organization_id, site.id)
    end

    test "shows an error when no site is chosen", %{conn: conn} do
      admin = user_fixture()

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock-take")

      lv |> element("button", "+ Start a stock take") |> render_click()

      html =
        lv
        |> form("#start-stock-take-form", stock_take: %{notes: "no site chosen"})
        |> render_submit()

      assert html =~ "Choose a site."
    end

    test "shows an error when the submitted site id is malformed", %{conn: conn} do
      admin = user_fixture()

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock-take")

      lv |> element("button", "+ Start a stock take") |> render_click()

      html = render_submit(lv, "start", %{"stock_take" => %{"site_id" => "not-a-number"}})

      assert html =~ "Choose a site."
    end

    test "index lists existing stock takes with a Continue/View action", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id, name: "Branch A"})
      draft = stock_take_fixture(%{organization_id: admin.organization_id, site_id: site.id})

      {:ok, lv, html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock-take")

      assert html =~ "Branch A"
      assert has_element?(lv, "a", "Continue")

      {:ok, _completed, _} =
        StockTakes.finalize_stock_take(admin.organization_id, draft.id, admin.id)

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock-take")
      assert has_element?(lv, "a", "View")
      refute has_element?(lv, "a", "Continue")
    end
  end

  describe "counting and variance review" do
    test "the counting screen shows product, GTIN, batch, expected, counted, and variance", %{
      conn: conn
    } do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id})

      batch =
        batch_fixture(%{
          organization_id: admin.organization_id,
          site_id: site.id,
          quantity: 50,
          batch_no: "LOT-COUNT-1"
        })

      stock_take = stock_take_fixture(%{organization_id: admin.organization_id, site_id: site.id})
      [entry] = stock_take.entries

      {:ok, lv, html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock-take/#{stock_take.id}")

      assert html =~ batch.gtin
      assert html =~ "LOT-COUNT-1"
      assert html =~ "50"

      lv
      |> form("#count-entry-form-#{entry.id}", %{"counted_quantity" => "45"})
      |> render_change()

      html = render(lv)
      assert html =~ "-5"

      assert %{counted_quantity: 45, variance: -5} =
               StockTakes.get_stock_take!(admin.organization_id, stock_take.id).entries
               |> List.first()
    end

    test "recording a count persists across navigating away and back (draft persistence)", %{
      conn: conn
    } do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id})
      batch_fixture(%{organization_id: admin.organization_id, site_id: site.id, quantity: 50})

      stock_take = stock_take_fixture(%{organization_id: admin.organization_id, site_id: site.id})
      [entry] = stock_take.entries

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock-take/#{stock_take.id}")

      lv
      |> form("#count-entry-form-#{entry.id}", %{"counted_quantity" => "48"})
      |> render_change()

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock-take/#{stock_take.id}")

      assert html =~ ~s(value="48")
    end

    test "flags a live conflict when the batch changed since counting began", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id})

      batch =
        batch_fixture(%{organization_id: admin.organization_id, site_id: site.id, quantity: 50})

      stock_take = stock_take_fixture(%{organization_id: admin.organization_id, site_id: site.id})
      [entry] = stock_take.entries

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock-take/#{stock_take.id}")

      lv
      |> form("#count-entry-form-#{entry.id}", %{"counted_quantity" => "45"})
      |> render_change()

      {:ok, _} = Batches.decrement_remaining_quantity(batch, 10)

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock-take/#{stock_take.id}")
      assert html =~ "Conflict"
    end

    test "shows a positive variance in an amber badge", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id})
      batch_fixture(%{organization_id: admin.organization_id, site_id: site.id, quantity: 40})

      stock_take = stock_take_fixture(%{organization_id: admin.organization_id, site_id: site.id})
      [entry] = stock_take.entries

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock-take/#{stock_take.id}")

      html =
        lv
        |> form("#count-entry-form-#{entry.id}", %{"counted_quantity" => "45"})
        |> render_change()

      assert html =~ "+5"
      assert html =~ "bg-amber-100"
    end

    test "shows an error for an invalid counted quantity", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id})
      batch_fixture(%{organization_id: admin.organization_id, site_id: site.id, quantity: 40})

      stock_take = stock_take_fixture(%{organization_id: admin.organization_id, site_id: site.id})
      [entry] = stock_take.entries

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock-take/#{stock_take.id}")

      html =
        lv
        |> form("#count-entry-form-#{entry.id}", %{"counted_quantity" => "-1"})
        |> render_change()

      assert html =~ "Enter a valid quantity."
    end

    test "shows an error when recording a count after the stock take is finalized", %{
      conn: conn
    } do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id})
      batch_fixture(%{organization_id: admin.organization_id, site_id: site.id, quantity: 40})

      stock_take = stock_take_fixture(%{organization_id: admin.organization_id, site_id: site.id})
      [entry] = stock_take.entries

      {:ok, _, _} = StockTakes.finalize_stock_take(admin.organization_id, stock_take.id, admin.id)

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock-take/#{stock_take.id}")

      html =
        render_change(lv, "record_count", %{"entry_id" => entry.id, "counted_quantity" => "5"})

      assert html =~ "This stock take has already been finalized."
    end
  end

  describe "finalizing" do
    test "finalizes, applies counted entries, and shows a summary", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id})

      batch =
        batch_fixture(%{organization_id: admin.organization_id, site_id: site.id, quantity: 50})

      stock_take = stock_take_fixture(%{organization_id: admin.organization_id, site_id: site.id})
      [entry] = stock_take.entries

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock-take/#{stock_take.id}")

      lv
      |> form("#count-entry-form-#{entry.id}", %{"counted_quantity" => "42"})
      |> render_change()

      lv |> element("button", "Finalize stock take") |> render_click()
      assert has_element?(lv, "#finalize-stock-take-modal")

      html = lv |> element("button", "Yes, finalize") |> render_click()

      assert html =~ "Stock take finalized"
      assert html =~ "1 batch updated"
      assert Batches.get_batch!(admin.organization_id, batch.id).remaining_quantity == 42

      refute has_element?(lv, "button", "Finalize stock take")
    end

    test "leaves a conflicted entry unapplied and reports it in the summary", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id})

      batch =
        batch_fixture(%{organization_id: admin.organization_id, site_id: site.id, quantity: 50})

      stock_take = stock_take_fixture(%{organization_id: admin.organization_id, site_id: site.id})
      [entry] = stock_take.entries

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock-take/#{stock_take.id}")

      lv
      |> form("#count-entry-form-#{entry.id}", %{"counted_quantity" => "42"})
      |> render_change()

      {:ok, _} = Batches.decrement_remaining_quantity(batch, 5)

      lv |> element("button", "Finalize stock take") |> render_click()
      html = lv |> element("button", "Yes, finalize") |> render_click()

      assert html =~ "0 batches updated"
      assert html =~ "1 left uncounted"
      assert Batches.get_batch!(admin.organization_id, batch.id).remaining_quantity == 45
    end

    test "cancel closes the finalize confirmation modal", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id})
      batch_fixture(%{organization_id: admin.organization_id, site_id: site.id, quantity: 40})

      stock_take = stock_take_fixture(%{organization_id: admin.organization_id, site_id: site.id})
      [entry] = stock_take.entries

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock-take/#{stock_take.id}")

      lv
      |> form("#count-entry-form-#{entry.id}", %{"counted_quantity" => "40"})
      |> render_change()

      lv |> element("button", "Finalize stock take") |> render_click()
      assert has_element?(lv, "#finalize-stock-take-modal")

      lv |> element("button", "Cancel") |> render_click()
      refute has_element?(lv, "#finalize-stock-take-modal")

      assert StockTakes.get_stock_take!(admin.organization_id, stock_take.id).status == :draft
    end

    test "shows an error when finalizing an already-finalized stock take", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id})

      stock_take = stock_take_fixture(%{organization_id: admin.organization_id, site_id: site.id})
      {:ok, _, _} = StockTakes.finalize_stock_take(admin.organization_id, stock_take.id, admin.id)

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock-take/#{stock_take.id}")

      html = render_click(lv, "finalize", %{})

      assert html =~ "This stock take has already been finalized."
    end
  end

  describe "show page details" do
    test "displays notes when present", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id})

      stock_take =
        stock_take_fixture(%{
          organization_id: admin.organization_id,
          site_id: site.id,
          notes: "Quarterly count"
        })

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock-take/#{stock_take.id}")
      assert html =~ "Quarterly count"
    end

    test "a dual-purpose site's stock take shows its name correctly", %{conn: conn} do
      admin = user_fixture()

      shared_site =
        site_fixture(%{
          organization_id: admin.organization_id,
          site_type: :pharmacy_lab,
          name: "Shared Clinic"
        })

      stock_take_fixture(%{organization_id: admin.organization_id, site_id: shared_site.id})

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock-take")
      assert html =~ "Shared Clinic"
    end
  end

  describe "access denial" do
    test "raises for a stock take belonging to a different organization", %{conn: conn} do
      admin = user_fixture()
      other_stock_take = stock_take_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        live(log_in_user(conn, admin), ~p"/pharmacy/stock-take/#{other_stock_take.id}")
      end
    end

    test "hides a stock take at a site outside the portal's capability from the index", %{
      conn: conn
    } do
      admin = user_fixture()
      lab_only_site = site_fixture(%{organization_id: admin.organization_id, site_type: :lab})
      stock_take_fixture(%{organization_id: admin.organization_id, site_id: lab_only_site.id})

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/pharmacy/stock-take")
      assert html =~ "No stock takes yet"
    end

    test "an admin cannot open a stock take at a site outside the portal's capability by URL",
         %{conn: conn} do
      admin = user_fixture()
      lab_only_site = site_fixture(%{organization_id: admin.organization_id, site_type: :lab})

      lab_only_stock_take =
        stock_take_fixture(%{organization_id: admin.organization_id, site_id: lab_only_site.id})

      assert_raise Ecto.NoResultsError, fn ->
        live(log_in_user(conn, admin), ~p"/pharmacy/stock-take/#{lab_only_stock_take.id}")
      end
    end

    test "a site-locked pharmacist cannot open another site's stock take in the same org", %{
      conn: conn
    } do
      admin = user_fixture()
      own_site = site_fixture(%{organization_id: admin.organization_id})
      other_site = site_fixture(%{organization_id: admin.organization_id})

      pharmacist =
        staff_fixture(%{
          organization_id: admin.organization_id,
          invited_by_id: admin.id,
          role: :pharmacist,
          site_id: own_site.id
        })

      other_stock_take =
        stock_take_fixture(%{organization_id: admin.organization_id, site_id: other_site.id})

      assert_raise Ecto.NoResultsError, fn ->
        live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock-take/#{other_stock_take.id}")
      end
    end
  end
end
