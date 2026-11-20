defmodule ThamaniDawaWeb.DistributorProductPaginationTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.DistributorFixtures
  import ThamaniDawa.ProductsFixtures

  test "page 2 shows only its own products, not page 1's too", %{conn: conn} do
    org = distributor_organization_fixture()
    site = warehouse_fixture(org.id)
    distributor = distributor_user_fixture(%{organization_id: org.id, site_id: site.id})

    for n <- 1..12 do
      product_fixture(%{
        organization_id: org.id,
        generic_name: "Paged Product #{String.pad_leading(Integer.to_string(n), 2, "0")}"
      })
    end

    conn = log_in_user(conn, distributor)

    {:ok, view, _html} = live(conn, ~p"/distributor/products")
    page1 = view |> element("#distributor-products") |> render()

    assert page1 =~ "Paged Product 01"
    refute page1 =~ "Paged Product 12"

    {:error, {:live_redirect, %{to: to}}} =
      view
      |> element("a", "2")
      |> render_click()

    {:ok, view, _html} = live(conn, to)
    page2 = view |> element("#distributor-products") |> render()

    assert page2 =~ "Paged Product 11"
    assert page2 =~ "Paged Product 12"
    refute page2 =~ "Paged Product 01"
    refute page2 =~ "Paged Product 10"
  end
end
