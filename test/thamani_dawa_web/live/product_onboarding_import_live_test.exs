defmodule ThamaniDawaWeb.ProductOnboardingImportLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.ProductsFixtures

  alias ThamaniDawaWeb.UserAuth

  defp log_in(conn, user), do: conn |> init_test_session(%{}) |> UserAuth.log_in_user(user)

  test "restores a parsed upload at the mapping step after refresh", %{conn: conn} do
    admin = user_fixture()

    {:ok, view, _html} =
      live(log_in(conn, admin), ~p"/org/products/new?return_to=onboarding")

    assert has_element?(view, "#onboarding-inventory-workflow[phx-hook]")

    csv = """
    Medicine / Product,Barcode (GTIN),Retail price (KES),Selling unit
    Paracetamol,6291041500213,100,U2
    """

    view
    |> element("#onboarding-inventory-workflow")
    |> render_hook("restore_onboarding_import", %{
      "version" => 1,
      "filename" => "products.csv",
      "content" => csv
    })

    assert has_element?(view, "#onboarding-mapping-form")

    assert has_element?(
             view,
             "select[name='mapping[gtin]'] option[value='Barcode (GTIN)'][selected]"
           )

    assert has_element?(
             view,
             "select[name='mapping[price]'] option[value='Retail price (KES)'][selected]"
           )
  end

  test "paginates the compact onboarding product catalog seven products at a time", %{conn: conn} do
    admin = user_fixture()

    products =
      for _index <- 1..11 do
        product_fixture(%{organization_id: admin.organization_id})
      end

    {:ok, view, _html} =
      live(log_in(conn, admin), ~p"/org/products/new?return_to=onboarding")

    first_product = List.first(products)
    last_product = List.last(products)

    assert has_element?(view, "#onboarding-products-pagination", "Page 1 of 2")
    assert has_element?(view, "#onboarding-product-#{first_product.id}")
    refute has_element?(view, "#onboarding-product-#{last_product.id}")

    view |> element("#onboarding-products-next") |> render_click()

    assert has_element?(view, "#onboarding-products-pagination", "Page 2 of 2")
    refute has_element?(view, "#onboarding-product-#{first_product.id}")
    assert has_element?(view, "#onboarding-product-#{last_product.id}")
  end

  test "replayed final step continues to the completion choice", %{conn: conn} do
    admin = user_fixture()

    {:ok, view, _html} =
      live(
        log_in(conn, admin),
        ~p"/org/products/new?return_to=onboarding&finish=tour"
      )

    view |> element("#onboarding-product-continue") |> render_click()
    assert_redirect(view, ~p"/onboarding?complete=1&force=1")
  end
end
