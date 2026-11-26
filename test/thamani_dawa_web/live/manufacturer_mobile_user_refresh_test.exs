defmodule ThamaniDawaWeb.ManufacturerMobileUserRefreshTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.DistributorFixtures
  import ThamaniDawa.ManufacturerFixtures

  test "refresh reloads the mobile users table", %{conn: conn} do
    organization = manufacturer_organization_fixture()
    site = manufacturing_site_fixture(organization.id)

    user =
      manufacturer_user_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        roles: [:admin, :manufacturer]
      })

    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/manufacturer/mobile-users")

    mobile_user = mobile_user_fixture(organization.id)
    refute has_element?(view, "#deactivate-mobile-user-#{mobile_user.id}")

    html = view |> element("#refresh-manufacturer-mobile-users") |> render_click()

    assert has_element?(view, "#deactivate-mobile-user-#{mobile_user.id}")
    assert html =~ "Mobile users refreshed."
  end
end
