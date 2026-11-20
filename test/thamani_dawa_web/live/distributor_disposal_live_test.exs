defmodule ThamaniDawaWeb.DistributorDisposalLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.DistributorFixtures

  alias ThamaniDawa.InventoryDisposals

  setup %{conn: conn} do
    distributor = distributor_user_fixture(%{roles: [:admin, :distributor]})
    %{conn: log_in(conn, distributor), distributor: distributor}
  end

  defp log_in(conn, user) do
    conn |> init_test_session(%{}) |> ThamaniDawaWeb.UserAuth.log_in_user(user)
  end

  test "a write-off cannot start when the warehouse has no expired stock", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/distributor/expiry-write-offs")

    assert has_element?(view, "#no-expired-stock", "No expired stock at this warehouse")
    assert has_element?(view, "#new-write-off[disabled]")
  end

  test "an expiry write-off starts from its own page", %{conn: conn, distributor: distributor} do
    batch_fixture(%{
      organization_id: distributor.organization_id,
      site_id: distributor.current_site_id,
      expiry_date: Date.add(Date.utc_today(), -1)
    })

    {:ok, view, _html} = live(conn, ~p"/distributor/expiry-write-offs")

    refute has_element?(view, "#no-expired-stock")
    refute has_element?(view, "#disposal-tab-expiry")
    refute has_element?(view, "#returns-tab-supplier")

    view |> element("#new-write-off") |> render_click()
    refute has_element?(view, "#write-off-form select[name='disposal[site_id]']")

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> form("#write-off-form", %{disposal: %{notes: "Past date"}})
             |> render_submit()

    {:ok, show, html} = live(conn, to)
    assert has_element?(show, "h1", "Expiry write-off")
    assert has_element?(show, "#add-batch-panel", "Add an expired lot")
    assert has_element?(show, "#disposal-items", "Lots to write off")
    assert has_element?(show, "#add-batch-form")
    refute html =~ "ff-surface-card"
    refute html =~ "text-slate-900"

    [disposal] = InventoryDisposals.list_disposals(distributor.organization_id)
    assert disposal.kind == :expiry
  end

  test "returns has supplier and customer tabs, and a supplier return follows the supplier tab",
       %{conn: conn, distributor: distributor} do
    {:ok, view, _html} = live(conn, ~p"/distributor/returns")

    assert has_element?(view, "#returns-tab-supplier[aria-selected='true']")
    assert has_element?(view, "#returns-tab-customer")

    view |> element("#new-supplier-return") |> render_click()
    refute has_element?(view, "#supplier-return-form select[name='disposal[site_id]']")
    refute has_element?(view, "#supplier-return-form input[name='disposal[reason]']")

    assert {:error, {:live_redirect, %{to: "/distributor/returns/" <> _id}}} =
             view
             |> form("#supplier-return-form", %{disposal: %{notes: "Damaged on arrival"}})
             |> render_submit()

    [disposal] = InventoryDisposals.list_disposals(distributor.organization_id)
    assert disposal.kind == :returned
  end
end
