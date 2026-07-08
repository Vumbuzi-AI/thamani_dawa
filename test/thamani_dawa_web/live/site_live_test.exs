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

    test "shows validation error when name is blank", %{conn: conn, admin: admin} do
      {:ok, lv, _} = live(log_in_user(conn, admin), ~p"/org/sites/new")

      lv
      |> form("#site-form", site: %{name: "", site_type: :pharmacy})
      |> render_change()

      assert render(lv) =~ "can&#39;t be blank"
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
  end
end
