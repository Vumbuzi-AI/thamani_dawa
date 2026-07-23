defmodule ThamaniDawaWeb.LayoutsTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures

  setup do
    admin = user_fixture()
    {:ok, admin: admin}
  end

  describe "organization sidebar navigation" do
    test "Sites appears immediately above Team in the main nav", %{conn: conn, admin: admin} do
      {:ok, lv, html} = live(log_in_user(conn, admin), ~p"/org/sites")

      assert has_element?(lv, "span[id='nav-label-/org/sites']")
      assert has_element?(lv, "span[id='nav-label-/org/team']")

      assert nav_order_index(html, "nav-label-/org/sites") <
               nav_order_index(html, "nav-label-/org/team")
    end

    test "highlights Sites as active when on the sites page, not Team", %{
      conn: conn,
      admin: admin
    } do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/sites")

      assert has_element?(lv, "a[style*='thamani-lime']", "Sites")
      refute has_element?(lv, "a[style*='thamani-lime']", "Team")
    end

    test "highlights Team as active when on the team page, not Sites", %{
      conn: conn,
      admin: admin
    } do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/team")

      assert has_element?(lv, "a[style*='thamani-lime']", "Team")
      refute has_element?(lv, "a[style*='thamani-lime']", "Sites")
    end
  end

  defp nav_order_index(html, id) do
    {index, _length} = :binary.match(html, id)
    index
  end
end
