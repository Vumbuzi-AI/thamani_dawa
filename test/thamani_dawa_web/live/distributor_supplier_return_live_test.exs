defmodule ThamaniDawaWeb.DistributorSupplierReturnLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.DistributorFixtures

  alias ThamaniDawa.InventoryDisposals

  setup %{conn: conn} do
    distributor = distributor_user_fixture(%{roles: [:admin, :distributor]})
    %{conn: log_in(conn, distributor), distributor: distributor}
  end

  defp log_in(conn, user) do
    conn |> init_test_session(%{}) |> ThamaniDawaWeb.UserAuth.log_in_user(user)
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
