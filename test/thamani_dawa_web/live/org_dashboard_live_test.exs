defmodule ThamaniDawaWeb.OrgDashboardLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
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

  test "site completion unlocks the dashboard without an activation checklist", %{
    conn: conn
  } do
    admin = user_fixture()

    primary_site =
      site_fixture(%{organization_id: admin.organization_id, address: "12 Market Street"})

    assert {:ok, _site} =
             Sites.update_site(primary_site, %{
               address: "12 Market Street",
               site_type: :pharmacy
             })

    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/org/dashboard")

    refute has_element?(view, "#organization-onboarding")
    assert has_element?(view, "#admin-dashboard-stats")
    assert has_element?(view, "#admin-dashboard-charts")
    assert has_element?(view, "input[name='search']")
    refute has_element?(view, "#activation-checklist")
  end

  test "a pharmacy-only organization does not see laboratory metrics", %{conn: conn} do
    admin = user_fixture()
    site_fixture(%{organization_id: admin.organization_id, site_type: :pharmacy})

    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/org/dashboard")

    assert has_element?(view, "#prescriptions-stat")
    assert has_element?(view, "#pending-prescriptions-stat")
    refute has_element?(view, "#lab-tests-done-stat")
    refute has_element?(view, "#pending-lab-orders-stat")
  end

  test "a lab-only organization does not see pharmacy metrics", %{conn: conn} do
    admin = user_fixture()
    site_fixture(%{organization_id: admin.organization_id, site_type: :lab})

    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/org/dashboard")

    refute has_element?(view, "#prescriptions-stat")
    refute has_element?(view, "#pending-prescriptions-stat")
    assert has_element?(view, "#lab-tests-done-stat")
    assert has_element?(view, "#pending-lab-orders-stat")
  end

  test "a combined organization sees both pharmacy and laboratory metrics", %{conn: conn} do
    admin = user_fixture()
    site_fixture(%{organization_id: admin.organization_id, site_type: :pharmacy_lab})

    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/org/dashboard")

    assert has_element?(view, "#prescriptions-stat")
    assert has_element?(view, "#pending-prescriptions-stat")
    assert has_element?(view, "#lab-tests-done-stat")
    assert has_element?(view, "#pending-lab-orders-stat")
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
               site_type: :pharmacy_lab
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
