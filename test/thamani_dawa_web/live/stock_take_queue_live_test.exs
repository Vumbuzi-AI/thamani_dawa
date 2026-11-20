defmodule ThamaniDawaWeb.StockTakeQueueLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.SitesFixtures
  import ThamaniDawa.StockTakesFixtures

  alias ThamaniDawa.Batches
  alias ThamaniDawa.StockTakes

  describe "index" do
    test "shows stock takes across every site in the organization", %{conn: conn} do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      site_a = site_fixture(%{organization_id: organization.id})
      site_b = site_fixture(%{organization_id: organization.id})

      _take_a = stock_take_fixture(%{organization_id: organization.id, site_id: site_a.id})
      _take_b = stock_take_fixture(%{organization_id: organization.id, site_id: site_b.id})

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/stock-takes")

      assert html =~ site_a.name
      assert html =~ site_b.name
    end
  end

  describe "approve" do
    test "approving a pending stock take applies counted quantities", %{conn: conn} do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      requester = user_fixture(%{organization_id: organization.id})

      take =
        stock_take_fixture(%{organization_id: organization.id, requested_by_id: requester.id})

      batch = batch_fixture(%{organization_id: organization.id, quantity: 40})
      {:ok, item} = StockTakes.add_item(take, batch)
      {:ok, _} = StockTakes.record_count(item, 33, requester.id)
      {:ok, _pending} = StockTakes.submit_stock_take(organization.id, take.id, requester.id)

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/stock-takes")

      lv
      |> element("button[phx-click='approve'][phx-value-id='#{take.id}']")
      |> render_click()

      assert Batches.get_batch!(organization.id, batch.id).remaining_quantity == 33
    end

    test "a draft admin self-serve stock take can also be approved directly", %{conn: conn} do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      take = stock_take_fixture(%{organization_id: organization.id, admin_id: admin.id})
      batch = batch_fixture(%{organization_id: organization.id, quantity: 10})
      {:ok, item} = StockTakes.add_item(take, batch)
      {:ok, _} = StockTakes.record_count(item, 7, admin.id)

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/stock-takes?status=draft")

      lv
      |> element("button[phx-click='approve'][phx-value-id='#{take.id}']")
      |> render_click()

      assert Batches.get_batch!(organization.id, batch.id).remaining_quantity == 7
    end
  end

  describe "reject" do
    test "rejecting requires a reason and makes no batch mutation", %{conn: conn} do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      requester = user_fixture(%{organization_id: organization.id})

      take =
        stock_take_fixture(%{organization_id: organization.id, requested_by_id: requester.id})

      batch = batch_fixture(%{organization_id: organization.id, quantity: 40})
      {:ok, item} = StockTakes.add_item(take, batch)
      {:ok, _} = StockTakes.record_count(item, 33, requester.id)
      {:ok, _pending} = StockTakes.submit_stock_take(organization.id, take.id, requester.id)

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/stock-takes/#{take.id}/reject")

      lv
      |> form("#reject-form", reject: %{rejection_reason: ""})
      |> render_submit()

      assert has_element?(lv, "#reject-stock-take-modal")

      lv
      |> form("#reject-form", reject: %{rejection_reason: "Recount needed"})
      |> render_submit()

      assert Batches.get_batch!(organization.id, batch.id).remaining_quantity == 40
    end
  end
end
