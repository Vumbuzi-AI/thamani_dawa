defmodule ThamaniDawaWeb.OnboardingLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures

  alias ThamaniDawa.Sites

  describe "mount" do
    test "redirects straight to the dashboard tour when the checklist is already complete", %{
      conn: conn
    } do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      user_fixture(%{organization_id: organization.id})

      site = site_fixture(%{organization_id: organization.id, address: "12 Market Street"})

      {:ok, _site} =
        Sites.update_site(site, %{address: "12 Market Street", activities: [:pharmacy]})

      site_fixture(%{organization_id: organization.id})

      product_fixture(%{organization_id: organization.id})

      assert {:error, {:live_redirect, %{to: "/org/dashboard?tour=1"}}} =
               live(log_in_user(conn, admin), ~p"/onboarding")
    end

    test "can safely replay the final product step after onboarding is complete", %{conn: conn} do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      user_fixture(%{organization_id: organization.id})
      site_fixture(%{organization_id: organization.id})
      site_fixture(%{organization_id: organization.id})
      product_fixture(%{organization_id: organization.id})

      {:ok, view, _html} =
        live(log_in_user(conn, admin), ~p"/onboarding?replay=first_product")

      assert has_element?(view, "#onboarding-panel-first_product")

      view |> element("#onboarding-cta") |> render_click()
      assert_redirect(view, ~p"/org/products/new?finish=tour&return_to=onboarding")
    end

    test "can replay team assignment before continuing to the product step", %{conn: conn} do
      admin = user_fixture()

      assert {:error,
              {:live_redirect,
               %{to: "/org/team/new?replay_next=first_product&return_to=onboarding"}}} =
               live(log_in_user(conn, admin), ~p"/onboarding?replay=invite_team")
    end

    test "shows a completion choice before entering the dashboard", %{conn: conn} do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      user_fixture(%{organization_id: organization.id})
      site_fixture(%{organization_id: organization.id})
      site_fixture(%{organization_id: organization.id})
      product_fixture(%{organization_id: organization.id})

      {:ok, view, _html} =
        live(log_in_user(conn, admin), ~p"/onboarding?complete=1")

      assert has_element?(view, "#onboarding-complete")
      assert has_element?(view, "#onboarding-take-tour[href='/org/dashboard?tour=1']")
      assert has_element?(view, "#onboarding-go-dashboard[href='/org/dashboard']")
    end

    test "shows the completion choice when the final product step is skipped", %{conn: conn} do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      user_fixture(%{organization_id: organization.id})
      site_fixture(%{organization_id: organization.id})
      site_fixture(%{organization_id: organization.id})

      {:ok, view, _html} =
        live(log_in_user(conn, admin), ~p"/onboarding?skip=first_product&complete=1")

      assert has_element?(view, "#onboarding-complete")
      assert has_element?(view, "#onboarding-take-tour")
    end

    test "welcomes a freshly signed-up admin before showing operational tasks", %{conn: conn} do
      admin = user_fixture()

      {:ok, view, html} = live(log_in_user(conn, admin), ~p"/onboarding")

      assert html =~ "Your workspace is ready"
      refute html =~ "Complete your primary site"
      assert has_element?(view, "#onboarding-shell")
      assert has_element?(view, "#onboarding-user", admin.name)
      assert has_element?(view, "#onboarding-progress[aria-label='Setup progress']")
      assert has_element?(view, "#onboarding-progress [style='width: 0.0%']")
      assert has_element?(view, "#onboarding-preview-invite_team")
      assert has_element?(view, "#onboarding-preview-add_branch")
      refute has_element?(view, "#onboarding-preview-first_supplier")
      assert has_element?(view, "#onboarding-start", "Start setup")
      refute has_element?(view, "#onboarding-exit")
      refute has_element?(view, "#onboarding-cta")

      view |> element("#onboarding-start") |> render_click()
      assert_redirect(view, ~p"/org/sites/new?return_to=onboarding")
    end

    test "laboratory-only organizations see only applicable operational tasks",
         %{conn: conn} do
      organization = organization_fixture(%{operating_models: [:laboratory]})
      admin = user_fixture(%{organization_id: organization.id})

      {:ok, view, html} = live(log_in_user(conn, admin), ~p"/onboarding")

      refute html =~ "Add your first product"
      refute html =~ "Add your inventory"
      refute html =~ "Add a supplier"
      refute html =~ "Complete your primary site"
      assert has_element?(view, "#onboarding-preview-invite_team")
      assert has_element?(view, "#onboarding-preview-add_branch")
    end
  end

  describe "skip and back" do
    test "skip advances to the next item without marking it done", %{conn: conn} do
      admin = user_fixture()
      user_fixture(%{organization_id: admin.organization_id})

      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/onboarding")

      assert has_element?(view, "#onboarding-cta", "Continue setup")

      view |> element("#onboarding-skip") |> render_click()

      assert has_element?(view, "#onboarding-panel-first_product")
      assert has_element?(view, "#onboarding-back")
    end

    test "back returns to the item that was just skipped", %{conn: conn} do
      admin = user_fixture()
      site_fixture(%{organization_id: admin.organization_id})
      site_fixture(%{organization_id: admin.organization_id})

      {:ok, view, _html} =
        live(log_in_user(conn, admin), ~p"/onboarding?skip=invite_team")

      assert has_element?(view, "#onboarding-cta", "Continue setup")

      view |> element("#onboarding-back") |> render_click()
      assert_redirect(view, ~p"/org/team/new?return_to=onboarding")
    end

    test "skipping every remaining item shows the completion choice", %{conn: conn} do
      organization = organization_fixture(%{operating_models: [:laboratory]})
      admin = user_fixture(%{organization_id: organization.id})
      user_fixture(%{organization_id: organization.id})

      site = site_fixture(%{organization_id: organization.id, address: "12 Market Street"})

      {:ok, _site} =
        Sites.update_site(site, %{address: "12 Market Street", activities: [:laboratory]})

      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/onboarding")

      view |> element("#onboarding-skip") |> render_click()

      assert has_element?(view, "#onboarding-complete")
      assert has_element?(view, "#onboarding-take-tour")
      assert has_element?(view, "#onboarding-go-dashboard")
    end
  end

  describe "completing an item" do
    test "start setup opens the first operational task directly", %{conn: conn} do
      admin = user_fixture()

      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/onboarding")
      view |> element("#onboarding-start") |> render_click()
      assert_redirect(view, ~p"/org/sites/new?return_to=onboarding")
    end

    test "an organization with a teammate resumes at the branch task", %{conn: conn} do
      admin = user_fixture()
      user_fixture(%{organization_id: admin.organization_id})

      {:ok, view, html} = live(log_in_user(conn, admin), ~p"/onboarding")

      refute html =~ "Complete your primary site"
      refute has_element?(view, "#onboarding-welcome")
      assert has_element?(view, "#onboarding-cta", "Continue setup")
    end
  end
end
