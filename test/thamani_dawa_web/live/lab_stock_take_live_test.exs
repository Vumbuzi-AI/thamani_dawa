defmodule ThamaniDawaWeb.LabStockTakeLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures

  alias ThamaniDawa.Batches
  alias ThamaniDawa.StockTakes

  defp lab_tech_at_site(org, site) do
    staff_fixture(%{organization_id: org.id, site_id: site.id, role: :lab_technician})
  end

  test "pharmacy-type batches never appear in a lab stock take's counting workspace", %{
    conn: conn
  } do
    org = organization_fixture()
    site = site_fixture(%{organization_id: org.id, activities: [:laboratory]})
    lab_tech = lab_tech_at_site(org, site)

    lab_product = product_fixture(%{organization_id: org.id, inventory_type: :lab_consumable})
    med_product = product_fixture(%{organization_id: org.id, inventory_type: :medicine})

    lab_batch =
      batch_fixture(%{
        organization_id: org.id,
        site_id: site.id,
        product_id: lab_product.id,
        quantity: 20
      })

    med_batch =
      batch_fixture(%{
        organization_id: org.id,
        site_id: site.id,
        product_id: med_product.id,
        quantity: 20
      })

    authed_conn = log_in_user(conn, lab_tech)
    {:ok, lv, _html} = live(authed_conn, ~p"/lab/stock-takes/new")

    {:ok, _show_lv, html} =
      lv
      |> form("#stock-take-form", stock_take: %{site_id: site.id, notes: "Lab count"})
      |> render_submit()
      |> follow_redirect(authed_conn)

    assert html =~ lab_batch.batch_no
    refute html =~ med_batch.batch_no
  end

  test "counting and submitting a lab stock take works end-to-end", %{conn: conn} do
    org = organization_fixture()
    site = site_fixture(%{organization_id: org.id, activities: [:laboratory]})
    lab_tech = lab_tech_at_site(org, site)
    lab_product = product_fixture(%{organization_id: org.id, inventory_type: :lab_consumable})

    batch =
      batch_fixture(%{
        organization_id: org.id,
        site_id: site.id,
        product_id: lab_product.id,
        quantity: 30
      })

    authed_conn = log_in_user(conn, lab_tech)
    {:ok, lv, _html} = live(authed_conn, ~p"/lab/stock-takes/new")

    {:ok, show_lv, _html} =
      lv
      |> form("#stock-take-form", stock_take: %{site_id: site.id})
      |> render_submit()
      |> follow_redirect(authed_conn)

    [item] =
      org.id
      |> StockTakes.list_stock_takes_for_site(site.id, :lab_consumable)
      |> List.first()
      |> then(&StockTakes.get_stock_take!(org.id, &1.id))
      |> Map.fetch!(:items)

    show_lv
    |> form("#count-form-#{item.id}", %{item_id: item.id, counted: "25"})
    |> render_submit()

    show_lv |> element("button", "Submit for approval") |> render_click()
    show_lv |> element("#confirm-submit-modal button", "Submit") |> render_click()

    assert render(show_lv) =~ "Pending"
    assert Batches.get_batch!(org.id, batch.id).remaining_quantity == 30
  end
end
