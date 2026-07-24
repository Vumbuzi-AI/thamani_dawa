defmodule ThamaniDawaWeb.LabStockTakeLiveTest do
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
      assert {:ok, _view, _html} = live(log_in_user(conn, admin), ~p"/lab/stock-take")
    end

    test "a lab technician can reach it", %{conn: conn} do
      lab_technician = staff_fixture(%{role: :lab_technician})
      assert {:ok, _view, _html} = live(log_in_user(conn, lab_technician), ~p"/lab/stock-take")
    end

    test "combined pharmacy/lab staff can reach it", %{conn: conn} do
      pharma_lab = staff_fixture(%{role: :pharma_lab})
      assert {:ok, _view, _html} = live(log_in_user(conn, pharma_lab), ~p"/lab/stock-take")
    end

    test "a pharmacist is redirected away", %{conn: conn} do
      pharmacist = staff_fixture(%{role: :pharmacist})

      assert {:error, {:redirect, %{to: "/"}}} =
               live(log_in_user(conn, pharmacist), ~p"/lab/stock-take")
    end

    test "an anonymous visitor is redirected away", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/lab/stock-take")
    end
  end

  describe "starting a stock take" do
    test "a site-locked lab technician starts one at their own site via the modal", %{conn: conn} do
      admin = user_fixture()

      site =
        site_fixture(%{organization_id: admin.organization_id, site_type: :lab, name: "Main Lab"})

      lab_technician =
        staff_fixture(%{
          organization_id: admin.organization_id,
          invited_by_id: admin.id,
          role: :lab_technician,
          site_id: site.id
        })

      batch_fixture(%{organization_id: admin.organization_id, site_id: site.id, quantity: 20})

      {:ok, lv, _html} = live(log_in_user(conn, lab_technician), ~p"/lab/stock-take")

      lv |> element("button", "+ Start a stock take") |> render_click()
      assert render(lv) =~ "Main Lab"

      lv
      |> form("#start-stock-take-form", stock_take: %{notes: "Monthly count"})
      |> render_submit()

      assert_redirect(lv)
      assert StockTakes.get_active_stock_take(admin.organization_id, site.id)
    end

    test "shows a dash when a site-locked staff member's home site isn't lab-capable", %{
      conn: conn
    } do
      admin = user_fixture()

      pharmacy_only_site =
        site_fixture(%{organization_id: admin.organization_id, site_type: :pharmacy})

      lab_technician =
        staff_fixture(%{
          organization_id: admin.organization_id,
          invited_by_id: admin.id,
          role: :lab_technician,
          site_id: pharmacy_only_site.id
        })

      {:ok, lv, _html} = live(log_in_user(conn, lab_technician), ~p"/lab/stock-take")

      lv |> element("button", "+ Start a stock take") |> render_click()
      assert render(lv) =~ "—"
    end

    test "shows an error instead of starting a second draft at the same site", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id, site_type: :lab})
      stock_take_fixture(%{organization_id: admin.organization_id, site_id: site.id})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/lab/stock-take")

      lv |> element("button", "+ Start a stock take") |> render_click()

      html =
        lv
        |> form("#start-stock-take-form", stock_take: %{site_id: to_string(site.id)})
        |> render_submit()

      assert html =~ "already has a stock take in progress"
    end

    test "only lab-capable sites are offered", %{conn: conn} do
      admin = user_fixture()

      lab_site =
        site_fixture(%{organization_id: admin.organization_id, name: "Lab Wing", site_type: :lab})

      site_fixture(%{organization_id: admin.organization_id, name: "Pharmacy Only"})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/lab/stock-take")

      lv |> element("button", "+ Start a stock take") |> render_click()
      html = render(lv)
      assert html =~ "Lab Wing"
      refute html =~ "Pharmacy Only"

      lv
      |> form("#start-stock-take-form", stock_take: %{site_id: to_string(lab_site.id)})
      |> render_submit()

      assert_redirect(lv)
      assert StockTakes.get_active_stock_take(admin.organization_id, lab_site.id)
    end

    test "cancel closes the start modal without starting anything", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id, site_type: :lab})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/lab/stock-take")

      lv |> element("button", "+ Start a stock take") |> render_click()
      assert has_element?(lv, "#start-stock-take-modal")

      lv |> element("button", "Cancel") |> render_click()
      refute has_element?(lv, "#start-stock-take-modal")
      refute StockTakes.get_active_stock_take(admin.organization_id, site.id)
    end

    test "shows an error when no site is chosen", %{conn: conn} do
      admin = user_fixture()

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/lab/stock-take")

      lv |> element("button", "+ Start a stock take") |> render_click()

      html =
        lv
        |> form("#start-stock-take-form", stock_take: %{notes: "no site chosen"})
        |> render_submit()

      assert html =~ "Choose a site."
    end

    test "shows an error when the submitted site id is malformed", %{conn: conn} do
      admin = user_fixture()

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/lab/stock-take")

      lv |> element("button", "+ Start a stock take") |> render_click()

      html = render_submit(lv, "start", %{"stock_take" => %{"site_id" => "not-a-number"}})

      assert html =~ "Choose a site."
    end
  end

  test "end-to-end: start, count, and finalize a stock take", %{conn: conn} do
    admin = user_fixture()
    site = site_fixture(%{organization_id: admin.organization_id, site_type: :lab})

    batch =
      batch_fixture(%{organization_id: admin.organization_id, site_id: site.id, quantity: 30})

    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/lab/stock-take")

    lv |> element("button", "+ Start a stock take") |> render_click()

    lv
    |> form("#start-stock-take-form", stock_take: %{site_id: to_string(site.id)})
    |> render_submit()

    assert_redirect(lv)

    active = StockTakes.get_active_stock_take(admin.organization_id, site.id)
    stock_take = StockTakes.get_stock_take!(admin.organization_id, active.id)
    [entry] = stock_take.entries

    {:ok, lv, _html} =
      live(log_in_user(conn, admin), ~p"/lab/stock-take/#{stock_take.id}")

    lv
    |> form("#count-entry-form-#{entry.id}", %{"counted_quantity" => "28"})
    |> render_change()

    lv |> element("button", "Finalize stock take") |> render_click()
    html = lv |> element("button", "Yes, finalize") |> render_click()

    assert html =~ "Stock take finalized"
    assert Batches.get_batch!(admin.organization_id, batch.id).remaining_quantity == 28
  end

  describe "counting and finalizing error paths" do
    test "leaves a conflicted entry unapplied and reports it in the summary", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id, site_type: :lab})

      batch =
        batch_fixture(%{organization_id: admin.organization_id, site_id: site.id, quantity: 50})

      stock_take = stock_take_fixture(%{organization_id: admin.organization_id, site_id: site.id})
      [entry] = stock_take.entries

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/lab/stock-take/#{stock_take.id}")

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

    test "shows an error for an invalid counted quantity", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id, site_type: :lab})
      batch_fixture(%{organization_id: admin.organization_id, site_id: site.id, quantity: 40})

      stock_take = stock_take_fixture(%{organization_id: admin.organization_id, site_id: site.id})
      [entry] = stock_take.entries

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/lab/stock-take/#{stock_take.id}")

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
      site = site_fixture(%{organization_id: admin.organization_id, site_type: :lab})
      batch_fixture(%{organization_id: admin.organization_id, site_id: site.id, quantity: 40})

      stock_take = stock_take_fixture(%{organization_id: admin.organization_id, site_id: site.id})
      [entry] = stock_take.entries

      {:ok, _, _} = StockTakes.finalize_stock_take(admin.organization_id, stock_take.id, admin.id)

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/lab/stock-take/#{stock_take.id}")

      html =
        render_change(lv, "record_count", %{"entry_id" => entry.id, "counted_quantity" => "5"})

      assert html =~ "This stock take has already been finalized."
    end

    test "cancel closes the finalize confirmation modal", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id, site_type: :lab})
      batch_fixture(%{organization_id: admin.organization_id, site_id: site.id, quantity: 40})

      stock_take = stock_take_fixture(%{organization_id: admin.organization_id, site_id: site.id})
      [entry] = stock_take.entries

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/lab/stock-take/#{stock_take.id}")

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
      site = site_fixture(%{organization_id: admin.organization_id, site_type: :lab})

      stock_take = stock_take_fixture(%{organization_id: admin.organization_id, site_id: site.id})
      {:ok, _, _} = StockTakes.finalize_stock_take(admin.organization_id, stock_take.id, admin.id)

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/lab/stock-take/#{stock_take.id}")

      html = render_click(lv, "finalize", %{})

      assert html =~ "This stock take has already been finalized."
    end
  end

  describe "show page details" do
    test "displays notes when present", %{conn: conn} do
      admin = user_fixture()
      site = site_fixture(%{organization_id: admin.organization_id, site_type: :lab})

      stock_take =
        stock_take_fixture(%{
          organization_id: admin.organization_id,
          site_id: site.id,
          notes: "Quarterly count"
        })

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/lab/stock-take/#{stock_take.id}")
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

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/lab/stock-take")
      assert html =~ "Shared Clinic"
    end
  end

  describe "access denial" do
    test "raises for a stock take belonging to a different organization", %{conn: conn} do
      admin = user_fixture()
      other_stock_take = stock_take_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        live(log_in_user(conn, admin), ~p"/lab/stock-take/#{other_stock_take.id}")
      end
    end

    test "hides a stock take at a site outside the portal's capability from the index", %{
      conn: conn
    } do
      admin = user_fixture()

      pharmacy_only_site =
        site_fixture(%{organization_id: admin.organization_id, site_type: :pharmacy})

      stock_take_fixture(%{organization_id: admin.organization_id, site_id: pharmacy_only_site.id})

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/lab/stock-take")
      assert html =~ "No stock takes yet"
    end

    test "an admin cannot open a stock take at a site outside the portal's capability by URL",
         %{conn: conn} do
      admin = user_fixture()

      pharmacy_only_site =
        site_fixture(%{organization_id: admin.organization_id, site_type: :pharmacy})

      pharmacy_only_stock_take =
        stock_take_fixture(%{
          organization_id: admin.organization_id,
          site_id: pharmacy_only_site.id
        })

      assert_raise Ecto.NoResultsError, fn ->
        live(log_in_user(conn, admin), ~p"/lab/stock-take/#{pharmacy_only_stock_take.id}")
      end
    end

    test "a site-locked lab technician cannot open another site's stock take in the same org", %{
      conn: conn
    } do
      admin = user_fixture()
      own_site = site_fixture(%{organization_id: admin.organization_id, site_type: :lab})
      other_site = site_fixture(%{organization_id: admin.organization_id, site_type: :lab})

      lab_technician =
        staff_fixture(%{
          organization_id: admin.organization_id,
          invited_by_id: admin.id,
          role: :lab_technician,
          site_id: own_site.id
        })

      other_stock_take =
        stock_take_fixture(%{organization_id: admin.organization_id, site_id: other_site.id})

      assert_raise Ecto.NoResultsError, fn ->
        live(log_in_user(conn, lab_technician), ~p"/lab/stock-take/#{other_stock_take.id}")
      end
    end
  end
end
