defmodule ThamaniDawaWeb.OrgDashboardLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.SitesFixtures

  alias ThamaniDawa.Sites

  test "a new organization must complete only its primary site before seeing the dashboard", %{
    conn: conn
  } do
    admin = user_fixture()

    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/org/dashboard")

    assert has_element?(view, "#organization-onboarding")
    assert has_element?(view, "#organization-onboarding-welcome")
    assert has_element?(view, "#complete-primary-site")
    refute has_element?(view, "#admin-dashboard-stats")
    refute has_element?(view, "#admin-dashboard-charts")
    refute has_element?(view, "#activation-checklist")
    refute has_element?(view, "input[name='search']")
  end

  test "site completion unlocks the dashboard while other checklist items remain", %{
    conn: conn
  } do
    admin = user_fixture()

    primary_site =
      site_fixture(%{organization_id: admin.organization_id, address: "12 Market Street"})

    assert {:ok, _site} =
             Sites.update_site(primary_site, %{
               address: "12 Market Street",
               activities: [:pharmacy]
             })

    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/org/dashboard")

    refute has_element?(view, "#organization-onboarding-welcome")
    assert has_element?(view, "#admin-dashboard-stats")
    assert has_element?(view, "#admin-dashboard-charts")
    assert has_element?(view, "input[name='search']")

    # The primary site is done, but the admin hasn't invited anyone, added
    # a branch, or added a product yet, so the checklist stays
    # visible for those.
    assert has_element?(view, "#organization-onboarding")
    refute has_element?(view, "#complete-primary-site")
    assert has_element?(view, "#onboarding-item-invite_team a", "Invite a teammate")
    assert has_element?(view, "#onboarding-item-add_branch a", "Add a branch")
    assert has_element?(view, "#onboarding-item-first_product a", "Add a product")
    refute has_element?(view, "#onboarding-item-first_supplier")
    refute has_element?(view, "#activation-checklist")
  end

  test "the checklist disappears once every applicable item is done", %{conn: conn} do
    organization = organization_fixture(%{operating_models: [:laboratory]})
    admin = user_fixture(%{organization_id: organization.id})
    user_fixture(%{organization_id: organization.id})

    primary_site =
      site_fixture(%{organization_id: organization.id, address: "12 Market Street"})

    assert {:ok, _site} =
             Sites.update_site(primary_site, %{
               address: "12 Market Street",
               activities: [:laboratory]
             })

    site_fixture(%{organization_id: organization.id, activities: [:laboratory]})

    {:ok, organization} = ThamaniDawa.Organizations.set_gs1_api_key(organization, "gs1-secret")

    {:ok, _organization} =
      ThamaniDawa.Organizations.set_epcis_api_key(organization, "facility", "facility-secret")

    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/org/dashboard")

    # A lab-only org has no product checklist item (that belongs to
    # pharmacy/distributor); the primary site is done, a teammate has
    # been invited, and a second site makes "Add a branch" done too, so
    # every applicable item is complete.
    refute has_element?(view, "#organization-onboarding")
  end

  test "the dashboard does not show laboratory metric cards", %{conn: conn} do
    admin = user_fixture()
    site_fixture(%{organization_id: admin.organization_id, activities: [:pharmacy, :laboratory]})

    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/org/dashboard")

    refute has_element?(view, "#lab-tests-done-stat")
    refute has_element?(view, "#pending-lab-orders-stat")
  end

  test "existing users can replay the product tour without it starting automatically", %{
    conn: conn
  } do
    admin = user_fixture()

    primary_site =
      site_fixture(%{organization_id: admin.organization_id, address: "12 Market Street"})

    assert {:ok, _site} =
             Sites.update_site(primary_site, %{
               address: "12 Market Street",
               activities: [:pharmacy, :laboratory]
             })

    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/org/dashboard")

    assert has_element?(view, "#start-product-tour")
    assert has_element?(view, "#organization-product-tour[data-auto-start='false']")
    assert has_element?(view, "[data-tour-target='/org/sites']")
    assert has_element?(view, "[data-tour-target='/org/products']")
    assert has_element?(view, "[data-tour-target='/org/suppliers']")
    assert has_element?(view, "[data-tour-target='/org/team']")
    refute has_element?(view, "[data-tour-target='/org/requisitions']")
  end

  test "the product tour starts after initial site setup", %{conn: conn} do
    admin = user_fixture()
    site_fixture(%{organization_id: admin.organization_id, address: "12 Market Street"})

    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/org/dashboard?tour=1")

    assert has_element?(view, "#organization-product-tour[data-auto-start='true']")
    assert has_element?(view, "#organization-product-tour [data-tour-card].z-\\[100\\]")
    refute has_element?(view, "#activation-checklist")
  end

  test "custom range rejects reversed dates and prevents future selections", %{conn: conn} do
    admin = user_fixture()
    site_fixture(%{organization_id: admin.organization_id, address: "12 Market Street"})

    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/org/dashboard")

    view |> element("button", "Filters") |> render_click()

    assert has_element?(view, "#filter-date-from-dp[data-max='today']")
    assert has_element?(view, "#filter-date-to-dp[data-max='today']")

    html =
      render_submit(view, "apply_custom_range", %{
        "from" => Date.utc_today() |> Date.to_iso8601(),
        "to" => Date.utc_today() |> Date.add(-1) |> Date.to_iso8601()
      })

    assert html =~ "Date From must be on or before Date To."
    assert has_element?(view, "#filter-date-from-dp")

    html =
      render_submit(view, "apply_custom_range", %{
        "from" => Date.utc_today() |> Date.to_iso8601(),
        "to" => Date.utc_today() |> Date.add(1) |> Date.to_iso8601()
      })

    assert html =~ "Date range cannot include future dates."
    assert has_element?(view, "#filter-date-to-dp")
  end
end
