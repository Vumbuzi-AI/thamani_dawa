defmodule ThamaniDawaWeb.SiteLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.SitesFixtures

  setup do
    admin = user_fixture()
    {:ok, admin: admin}
  end

  describe "index" do
    test "lists only own org's sites", %{conn: conn, admin: admin} do
      _own = site_fixture(%{organization_id: admin.organization_id, name: "Own Branch"})
      _other = site_fixture(%{name: "Other Branch"})

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/sites")

      assert html =~ "Own Branch"
      refute html =~ "Other Branch"
    end

    test "searches by name or address", %{conn: conn, admin: admin} do
      site_fixture(%{organization_id: admin.organization_id, name: "Nairobi Branch"})
      site_fixture(%{organization_id: admin.organization_id, name: "Mombasa Branch"})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/sites")

      lv |> form("form[phx-change='search']", search: "nairobi") |> render_change()

      html = render(lv)
      assert html =~ "Nairobi Branch"
      refute html =~ "Mombasa Branch"
    end

    test "filters by type", %{conn: conn, admin: admin} do
      site_fixture(%{
        organization_id: admin.organization_id,
        name: "Pharmacy One",
        site_type: :pharmacy
      })

      site_fixture(%{organization_id: admin.organization_id, name: "Lab One", site_type: :lab})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/sites")

      lv
      |> form("#sites-filters-form", filters: %{site_type: "lab"})
      |> render_submit()

      html = render(lv)
      assert html =~ "Lab One"
      refute html =~ "Pharmacy One"
      assert html =~ "Type: Lab"
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

      lv
      |> form("#sites-filters-form", filters: %{status: "inactive"})
      |> render_submit()

      html = render(lv)
      assert html =~ inactive.name
      refute html =~ active.name
      assert html =~ "Status: Inactive"
    end

    test "a stray validate event on the plain index view is a no-op", %{conn: conn, admin: admin} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/sites")

      html = render_change(lv, "validate", %{})

      assert html =~ "Sites"
    end
  end

  describe "new" do
    test "renders form with stable input IDs", %{conn: conn, admin: admin} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/sites/new")

      assert has_element?(lv, "#site-name")
      assert has_element?(lv, "#site-gln")
      assert has_element?(lv, "#site-address")
      assert has_element?(lv, "#site-capability")
      assert has_element?(lv, "#site-capability-pharmacy")
      assert has_element?(lv, "#site-capability-lab")
      assert has_element?(lv, "#site-capability-pharmacy_lab")
      assert has_element?(lv, "#site-capability-warehouse")
    end

    test "creates a pharmacy site", %{conn: conn, admin: admin} do
      {:ok, lv, _} = live(log_in_user(conn, admin), ~p"/org/sites/new")

      lv
      |> form("#site-form",
        site: %{
          name: "Pharmacy Branch",
          site_type: :pharmacy,
          gln: "0612345678901",
          address: "1 Test St"
        }
      )
      |> render_submit()

      assert render(lv) =~ "Pharmacy Branch"
    end

    test "creates a lab site", %{conn: conn, admin: admin} do
      {:ok, lv, _} = live(log_in_user(conn, admin), ~p"/org/sites/new")

      lv
      |> form("#site-form",
        site: %{
          name: "Lab Branch",
          site_type: :lab,
          gln: "0612345678902",
          address: "2 Test St"
        }
      )
      |> render_submit()

      assert render(lv) =~ "Lab Branch"
    end

    test "creates a pharmacy_lab site", %{conn: conn, admin: admin} do
      {:ok, lv, _} = live(log_in_user(conn, admin), ~p"/org/sites/new")

      lv
      |> form("#site-form",
        site: %{
          name: "Combined Branch",
          site_type: :pharmacy_lab,
          gln: "0612345678903",
          address: "3 Test St"
        }
      )
      |> render_submit()

      assert render(lv) =~ "Combined Branch"
    end

    test "creates a warehouse site", %{conn: conn, admin: admin} do
      {:ok, lv, _} = live(log_in_user(conn, admin), ~p"/org/sites/new")

      lv
      |> form("#site-form",
        site: %{
          name: "Warehouse Branch",
          site_type: :warehouse,
          gln: "0612345678904",
          address: "4 Test St"
        }
      )
      |> render_submit()

      assert render(lv) =~ "Warehouse Branch"

      site = ThamaniDawa.Repo.get_by!(ThamaniDawa.Sites.Site, name: "Warehouse Branch")
      assert site.site_type == :warehouse
    end

    test "shows validation error when name is blank", %{conn: conn, admin: admin} do
      {:ok, lv, _} = live(log_in_user(conn, admin), ~p"/org/sites/new")

      lv
      |> form("#site-form", site: %{name: "", site_type: :pharmacy})
      |> render_change()

      assert render(lv) =~ "can&#39;t be blank"
    end

    test "shows an error and does not create a site with a duplicate GLN", %{
      conn: conn,
      admin: admin
    } do
      site_fixture(%{organization_id: admin.organization_id, gln: "0699999999999"})

      {:ok, lv, _} = live(log_in_user(conn, admin), ~p"/org/sites/new")

      html =
        lv
        |> form("#site-form",
          site: %{
            name: "Second Branch",
            site_type: :pharmacy,
            gln: "0699999999999",
            address: "5 Test St"
          }
        )
        |> render_submit()

      assert html =~ "has already been taken"
      refute ThamaniDawa.Repo.get_by(ThamaniDawa.Sites.Site, name: "Second Branch")
    end
  end

  describe "edit" do
    test "persists name, address, GLN, and capability changes", %{conn: conn, admin: admin} do
      site =
        site_fixture(%{
          organization_id: admin.organization_id,
          name: "Old Name",
          site_type: :pharmacy
        })

      {:ok, lv, _} = live(log_in_user(conn, admin), ~p"/org/sites/#{site.id}/edit")

      lv
      |> form("#site-form",
        site: %{
          name: "New Name",
          address: "Updated St",
          gln: "6291041500213",
          site_type: :lab
        }
      )
      |> render_submit()

      html = render(lv)
      assert html =~ "New Name"
      assert html =~ "Updated St"
      assert html =~ "6291041500213"
    end

    test "shows an error and does not persist an invalid edit", %{conn: conn, admin: admin} do
      site =
        site_fixture(%{
          organization_id: admin.organization_id,
          name: "Keep This Name",
          site_type: :pharmacy
        })

      {:ok, lv, _} = live(log_in_user(conn, admin), ~p"/org/sites/#{site.id}/edit")

      html =
        lv
        |> form("#site-form", site: %{name: "", site_type: :pharmacy})
        |> render_submit()

      assert html =~ "can&#39;t be blank"

      assert %{name: "Keep This Name"} =
               ThamaniDawa.Sites.get_site!(admin.organization_id, site.id)
    end
  end
end
