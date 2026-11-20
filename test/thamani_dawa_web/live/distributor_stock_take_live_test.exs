defmodule ThamaniDawaWeb.DistributorStockTakeLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.DistributorFixtures
  import ThamaniDawa.StockTakesFixtures

  alias ThamaniDawa.Batches
  alias ThamaniDawa.StockTakes

  test "lists and starts a stock take for a distribution site", %{conn: conn} do
    org = distributor_organization_fixture()
    site = warehouse_fixture(org.id)
    distributor = distributor_user_fixture(%{organization_id: org.id, site_id: site.id})
    take = stock_take_fixture(%{organization_id: org.id, site_id: site.id})

    {:ok, _lv, html} = live(log_in_user(conn, distributor), ~p"/distributor/stock-takes")

    assert html =~ site.name
    assert html =~ take.notes
  end

  test "counting and approving a distributor stock take updates batch quantities", %{conn: conn} do
    org = distributor_organization_fixture()
    site = warehouse_fixture(org.id)
    distributor = distributor_user_fixture(%{organization_id: org.id, site_id: site.id})
    admin = user_fixture(%{organization_id: org.id})
    batch = batch_fixture(%{organization_id: org.id, site_id: site.id, quantity: 60})

    authed_conn = log_in_user(conn, distributor)
    {:ok, lv, html} = live(authed_conn, ~p"/distributor/stock-takes/new")

    assert html =~ site.name
    refute html =~ "Choose a warehouse"

    {:ok, show_lv, _html} =
      lv
      |> form("#stock-take-form", stock_take: %{site_id: site.id})
      |> render_submit()
      |> follow_redirect(authed_conn)

    [item] =
      org.id
      |> StockTakes.list_stock_takes_for_site(site.id, :medicine)
      |> List.first()
      |> then(&StockTakes.get_stock_take!(org.id, &1.id))
      |> Map.fetch!(:items)

    show_lv
    |> form("#count-form-#{item.id}", %{item_id: item.id, counted: "55"})
    |> render_submit()

    show_lv |> element("button", "Submit for approval") |> render_click()
    show_lv |> element("#confirm-submit-modal button", "Submit") |> render_click()

    stock_take =
      org.id
      |> StockTakes.list_stock_takes_for_site(site.id, :medicine)
      |> List.first()

    {:ok, _approved} = StockTakes.approve_stock_take(org.id, stock_take.id, admin.id)

    assert Batches.get_batch!(org.id, batch.id).remaining_quantity == 55
  end
end
