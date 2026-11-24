defmodule ThamaniDawaWeb.SiteLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.SitesFixtures

  setup do
    admin = user_fixture()
    {:ok, admin: admin}
  end

  defp admin_with_operating_models(operating_models) do
    organization = organization_fixture(%{operating_models: operating_models})
    user_fixture(%{organization_id: organization.id})
  end

  describe "index" do
    test "lists only own org's sites", %{conn: conn, admin: admin} do
      own = site_fixture(%{organization_id: admin.organization_id, name: "Own Branch"})
      _other = site_fixture(%{name: "Other Branch"})

      {:ok, lv, html} = live(log_in_user(conn, admin), ~p"/org/sites")

      assert html =~ "Own Branch"
      refute html =~ "Other Branch"
      assert has_element?(lv, "#site-card-#{own.id}")
      assert has_element?(lv, "#btn-edit-site-#{own.id}")
    end

    test "searches by name or address", %{conn: conn, admin: admin} do
      site_fixture(%{organization_id: admin.organization_id, name: "Nairobi Branch"})
      site_fixture(%{organization_id: admin.organization_id, name: "Mombasa Branch"})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/sites")

      lv |> form("form[phx-change='search']", search: "nairobi") |> render_change()

      html = render(element(lv, "#sites-table"))
      assert html =~ "Nairobi Branch"
      refute html =~ "Mombasa Branch"
    end

    test "filters by activity", %{conn: conn, admin: admin} do
      site_fixture(%{
        organization_id: admin.organization_id,
        name: "Pharmacy One",
        activities: [:pharmacy]
      })

      site_fixture(%{
        organization_id: admin.organization_id,
        name: "Lab One",
        activities: [:laboratory]
      })

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/sites")

      render_click(lv, "set_filter", %{"field" => "activities", "value" => "laboratory"})

      table_html = render(element(lv, "#sites-table"))
      assert table_html =~ "Lab One"
      refute table_html =~ "Pharmacy One"
      assert has_element?(lv, "#sites-chip-activities", "Laboratory")
    end

    test "filters by active status", %{conn: conn, admin: admin} do
      active = site_fixture(%{organization_id: admin.organization_id, name: "Active Site"})

      inactive =
        site_fixture(%{
          organization_id: admin.organization_id,
          name: "Inactive Site",
          is_active: false
        })

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/sites")

      render_click(lv, "set_filter", %{"field" => "status", "value" => "inactive"})

      table_html = render(element(lv, "#sites-table"))
      assert table_html =~ inactive.name
      refute table_html =~ active.name
      assert has_element?(lv, "#sites-chip-status", "Inactive")
    end

    test "a stray validate event on the plain index view is a no-op", %{conn: conn, admin: admin} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/sites")

      html = render_change(lv, "validate", %{})

      assert html =~ "Sites"
    end
  end

  describe "new" do
    test "renders the GLN field first, gated on GS1 verification", %{conn: conn, admin: admin} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/sites/new")

      assert has_element?(lv, "#site-gln[required]")
      refute has_element?(lv, "#site-name")
      refute has_element?(lv, "#site-capability")
    end

    test "does not look up a branch GLN outside the verified company prefix", %{conn: conn} do
      organization = organization_with_prefix_fixture(%{operating_models: [:pharmacy]})
      admin = user_fixture(%{organization_id: organization.id})
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/sites/new")

      lv |> form("#site-form", site: %{gln: "9506000134352"}) |> render_submit()

      assert has_element?(
               lv,
               "#site-gln-prefix-mismatch",
               "This GLN does not belong to your verified GS1 company prefix."
             )

      refute has_element?(lv, "#site-form", "Checking with the GS1 registry")
    end

    test "checks for an existing branch GLN before querying GS1", %{conn: conn, admin: admin} do
      site_fixture(%{organization_id: admin.organization_id, gln: "0614141000128"})
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/sites/new")

      lv |> form("#site-form", site: %{gln: "0614141000128"}) |> render_submit()

      assert has_element?(lv, "#site-form", "This GLN is already registered to another location.")
      refute has_element?(lv, "#site-form", "Checking with the GS1 registry")
    end

    test "verifying the GLN reveals activity choices gated by the org's operating models", %{
      conn: conn
    } do
      admin = admin_with_operating_models([:pharmacy, :laboratory, :distributor])
      {:ok, lv, _} = live(log_in_user(conn, admin), ~p"/org/sites/new")

      lv |> form("#site-form", site: %{gln: "0614141000128"}) |> render_submit()
      render_async(lv, 5_000)

      html = render(lv)
      assert html =~ "Verified with GS1"
      assert html =~ "Retail pharmacy"
      assert html =~ "Diagnostic laboratory"
      assert html =~ "Pharmaceutical distributor"
      assert has_element?(lv, "#site-name[value='Test Licensee']")
      assert has_element?(lv, "#site-address[value='Nairobi, Kenya']")
    end

    test "offers only the single matching activity when the org has one operating model", %{
      conn: conn,
      admin: admin
    } do
      {:ok, lv, _} = live(log_in_user(conn, admin), ~p"/org/sites/new")

      lv |> form("#site-form", site: %{gln: "0614141000128"}) |> render_submit()
      render_async(lv, 5_000)

      assert has_element?(lv, "input[name='site[activity_choice]'][value='pharmacy']")
      refute has_element?(lv, "input[name='site[activity_choice]'][value='laboratory']")
      refute has_element?(lv, "#site-form", "Activity at this location")
    end

    test "creates a pharmacy site", %{conn: conn, admin: admin} do
      {:ok, lv, _} = live(log_in_user(conn, admin), ~p"/org/sites/new")

      lv |> form("#site-form", site: %{gln: "0614141000128"}) |> render_submit()
      render_async(lv, 5_000)

      lv
      |> form("#site-form", site: %{gln: "0614141000128", activity_choice: "pharmacy"})
      |> render_submit()

      assert render(lv) =~ "Test Licensee"

      site = ThamaniDawa.Repo.get_by!(ThamaniDawa.Sites.Site, gln: "0614141000128")
      assert site.activities == [:pharmacy]
      assert site.name == "Test Licensee"
    end

    test "creates a lab site", %{conn: conn} do
      admin = admin_with_operating_models([:laboratory])
      {:ok, lv, _} = live(log_in_user(conn, admin), ~p"/org/sites/new")

      lv |> form("#site-form", site: %{gln: "6160001000004"}) |> render_submit()
      render_async(lv, 5_000)

      lv
      |> form("#site-form", site: %{gln: "6160001000004", activity_choice: "laboratory"})
      |> render_submit()

      site = ThamaniDawa.Repo.get_by!(ThamaniDawa.Sites.Site, gln: "6160001000004")
      assert site.activities == [:laboratory]
    end

    test "creates a pharmacy_lab site", %{conn: conn} do
      admin = admin_with_operating_models([:pharmacy, :laboratory])
      {:ok, lv, _} = live(log_in_user(conn, admin), ~p"/org/sites/new")

      lv |> form("#site-form", site: %{gln: "6160001000011"}) |> render_submit()
      render_async(lv, 5_000)

      lv
      |> form("#site-form", site: %{gln: "6160001000011", activity_choice: "pharmacy_laboratory"})
      |> render_submit()

      site = ThamaniDawa.Repo.get_by!(ThamaniDawa.Sites.Site, gln: "6160001000011")
      assert site.activities == [:pharmacy, :laboratory]
    end

    test "creates a warehouse site", %{conn: conn} do
      admin = admin_with_operating_models([:distributor])
      {:ok, lv, _} = live(log_in_user(conn, admin), ~p"/org/sites/new")

      lv |> form("#site-form", site: %{gln: "0614141000128"}) |> render_submit()
      render_async(lv, 5_000)

      lv
      |> form("#site-form", site: %{gln: "0614141000128", activity_choice: "distribution"})
      |> render_submit()

      site = ThamaniDawa.Repo.get_by!(ThamaniDawa.Sites.Site, gln: "0614141000128")
      assert site.activities == [:distribution]
      assert site.gln == "0614141000128"
    end

    test "does not save while the GLN is still unverified", %{conn: conn, admin: admin} do
      {:ok, lv, _} = live(log_in_user(conn, admin), ~p"/org/sites/new")

      html = lv |> form("#site-form", site: %{gln: "0614141000128"}) |> render_submit()

      assert html =~ "Checking the GLN with the GS1 registry"
      refute ThamaniDawa.Repo.get_by(ThamaniDawa.Sites.Site, gln: "0614141000128")
    end
  end

  describe "edit" do
    test "uses the onboarding site-type selector and marks the current type", %{conn: conn} do
      admin = admin_with_operating_models([:pharmacy, :laboratory, :distributor])

      site =
        site_fixture(%{
          organization_id: admin.organization_id,
          activities: [:pharmacy, :laboratory]
        })

      {:ok, lv, _} = live(log_in_user(conn, admin), ~p"/org/sites/#{site.id}/edit")

      assert has_element?(
               lv,
               ~s(input[type="radio"][name="site[activity_choice]"][value="pharmacy_laboratory"]:checked)
             )

      assert has_element?(
               lv,
               ~s(input[type="radio"][name="site[activity_choice]"][value="distribution"])
             )

      refute has_element?(lv, "#site-capability")
    end

    test "completing the signup-created site opens the dashboard tour", %{
      conn: conn,
      admin: admin
    } do
      assert {:ok, site} =
               ThamaniDawa.Sites.create_default_site(admin.organization_id, "Primary Site")

      {:ok, lv, _} =
        live(
          log_in_user(conn, admin),
          ~p"/org/sites/#{site.id}/edit?return_to=dashboard"
        )

      lv
      |> form("#site-form",
        site: %{
          name: "Primary Site",
          address: "12 Market Street",
          activity_choice: "pharmacy",
          gln: "0614141000128"
        }
      )
      |> render_submit()

      assert_redirect(lv, ~p"/org/dashboard?tour=1")
    end

    test "persists name, address, and site type changes", %{conn: conn} do
      admin = admin_with_operating_models([:pharmacy, :laboratory])

      site =
        site_fixture(%{
          organization_id: admin.organization_id,
          name: "Old Name",
          activities: [:pharmacy]
        })

      {:ok, lv, _} = live(log_in_user(conn, admin), ~p"/org/sites/#{site.id}/edit")

      lv
      |> form("#site-form",
        site: %{
          name: "New Name",
          address: "Updated St",
          activity_choice: "laboratory"
        }
      )
      |> render_submit()

      html = render(lv)
      assert html =~ "New Name"
      assert html =~ "Updated St"
    end

    test "shows an error and does not persist an invalid edit", %{conn: conn, admin: admin} do
      site =
        site_fixture(%{
          organization_id: admin.organization_id,
          name: "Keep This Name",
          activities: [:pharmacy]
        })

      {:ok, lv, _} = live(log_in_user(conn, admin), ~p"/org/sites/#{site.id}/edit")

      html =
        lv
        |> form("#site-form", site: %{name: "", activity_choice: "pharmacy"})
        |> render_submit()

      assert html =~ "can&#39;t be blank"

      assert %{name: "Keep This Name"} =
               ThamaniDawa.Sites.get_site!(admin.organization_id, site.id)
    end
  end

  describe "GLN picker" do
    setup do
      organization = organization_fixture(%{operating_models: [:distributor, :manufacturer]})
      {:ok, organization} = ThamaniDawa.Organizations.set_gs1_api_key(organization, "gs1-secret")
      {:ok, admin: user_fixture(%{organization_id: organization.id})}
    end

    test "lists the member's GLNs and filters them by name", %{conn: conn, admin: admin} do
      {:ok, lv, _} = live(log_in_user(conn, admin), ~p"/org/sites/new")

      assert has_element?(lv, "#gln-option-0614141000784")
      assert has_element?(lv, "#gln-option-0614141000456")

      lv
      |> form("#site-form")
      |> render_change(%{"_target" => ["gln_query"], "gln_query" => "annex"})

      refute has_element?(lv, "#gln-option-0614141000784")
      assert has_element?(lv, "#gln-option-0614141000456")
    end

    test "picking a GLN selects it and offers manufacturer activities", %{
      conn: conn,
      admin: admin
    } do
      {:ok, lv, _} = live(log_in_user(conn, admin), ~p"/org/sites/new")

      lv |> element("#gln-option-0614141000784 button") |> render_click()
      render_async(lv, 5_000)

      assert has_element?(lv, "#gln-picker-selected")
      html = render(lv)
      assert html =~ "Pharmaceutical manufacturer"
      assert html =~ "Manufacturer + distributor"
    end
  end
end
