defmodule ThamaniDawaWeb.StockTakeLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.SitesFixtures
  import ThamaniDawa.StockTakesFixtures

  alias ThamaniDawa.Batches
  alias ThamaniDawa.StockTakes

  defp pharmacist_at_site(org, site) do
    staff_fixture(%{organization_id: org.id, site_id: site.id})
  end

  describe "Index" do
    test "lists stock takes for the organization", %{conn: conn} do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id})
      pharmacist = pharmacist_at_site(org, site)
      take = stock_take_fixture(%{organization_id: org.id, site_id: site.id})

      {:ok, _lv, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock-takes")

      assert html =~ site.name
      assert html =~ take.notes
    end

    test "does not list another organization's stock takes", %{conn: conn} do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id})
      pharmacist = pharmacist_at_site(org, site)

      other_org = organization_fixture()
      other_take = stock_take_fixture(%{organization_id: other_org.id})

      {:ok, _lv, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock-takes")

      refute html =~ other_take.notes
    end

    test "opens the new stock take modal on /new", %{conn: conn} do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id})
      pharmacist = pharmacist_at_site(org, site)

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock-takes/new")

      assert has_element?(lv, "#stock-take-modal")
      assert render(lv) =~ "Start a new stock take"
    end

    test "cancelling the modal patches back to the list", %{conn: conn} do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id})
      pharmacist = pharmacist_at_site(org, site)

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock-takes/new")

      lv |> element("#stock-take-modal button[aria-label='Cancel']") |> render_click()

      assert_patch(lv, ~p"/pharmacy/stock-takes")
      refute has_element?(lv, "#stock-take-modal")
    end

    test "creating a stock take navigates to the counting workspace", %{conn: conn} do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id})
      pharmacist = pharmacist_at_site(org, site)
      authed_conn = log_in_user(conn, pharmacist)

      {:ok, lv, _html} = live(authed_conn, ~p"/pharmacy/stock-takes/new")

      {:ok, _show_lv, html} =
        lv
        |> form("#stock-take-form",
          stock_take: %{site_id: site.id, notes: "Quarterly count"}
        )
        |> render_submit()
        |> follow_redirect(authed_conn)

      assert html =~ site.name
      assert html =~ "Stock take"
    end

    test "validation error on missing site_id stays in the modal", %{conn: conn} do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id})
      pharmacist = pharmacist_at_site(org, site)

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock-takes/new")

      html =
        lv
        |> form("#stock-take-form", stock_take: %{site_id: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert has_element?(lv, "#stock-take-modal")
    end
  end

  describe "Show (counting workspace)" do
    test "shows the stock take and its items", %{conn: conn} do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id})
      pharmacist = pharmacist_at_site(org, site)
      take = stock_take_fixture(%{organization_id: org.id, site_id: site.id})
      batch = batch_fixture(%{organization_id: org.id, site_id: site.id})
      StockTakes.add_item(take, batch)

      {:ok, _lv, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock-takes/#{take.id}")

      assert html =~ site.name
      assert html =~ batch.batch_no
    end

    test "recording a count updates the item", %{conn: conn} do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id})
      pharmacist = pharmacist_at_site(org, site)
      take = stock_take_fixture(%{organization_id: org.id, site_id: site.id})
      batch = batch_fixture(%{organization_id: org.id, site_id: site.id, quantity: 50})
      {:ok, item} = StockTakes.add_item(take, batch)

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock-takes/#{take.id}")

      lv
      |> form("#count-form-#{item.id}", %{item_id: item.id, counted: "42"})
      |> render_submit()

      html = render(lv)
      assert html =~ "Count recorded."
      assert html =~ "42"
    end

    test "finalizing the stock take updates batch quantities", %{conn: conn} do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id})
      pharmacist = pharmacist_at_site(org, site)
      take = stock_take_fixture(%{organization_id: org.id, site_id: site.id})
      batch = batch_fixture(%{organization_id: org.id, site_id: site.id, quantity: 100})
      {:ok, item} = StockTakes.add_item(take, batch)
      StockTakes.record_count(item, 87, pharmacist.id)

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/stock-takes/#{take.id}")

      lv
      |> element("button", "Finalize stock take")
      |> render_click()

      assert render(lv) =~ "Stock take finalized"
      assert Batches.get_batch!(org.id, batch.id).remaining_quantity == 87
    end

    test "cannot access another organization's stock take", %{conn: conn} do
      org_a = organization_fixture()
      site_a = site_fixture(%{organization_id: org_a.id})
      pharmacist_a = pharmacist_at_site(org_a, site_a)

      org_b = organization_fixture()
      take_b = stock_take_fixture(%{organization_id: org_b.id})

      assert_raise Ecto.NoResultsError, fn ->
        live(log_in_user(conn, pharmacist_a), ~p"/pharmacy/stock-takes/#{take_b.id}")
      end
    end
  end
end
