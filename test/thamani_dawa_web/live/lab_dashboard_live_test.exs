defmodule ThamaniDawaWeb.LabDashboardLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures

  describe "lab dashboard pending batches sidebar badge" do
    test "shows a count badge on Receive stock when batches are awaiting receipt at this lab site",
         %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id, site_type: :lab})

      lab_tech =
        staff_fixture(%{
          organization_id: organization.id,
          role: :lab_technician,
          site_id: site.id
        })

      product = product_fixture(%{organization_id: organization.id})

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        pending: true
      })

      {:ok, lv, _html} = live(log_in_user(conn, lab_tech), ~p"/lab")

      assert has_element?(lv, "a[href='/lab/receive-stock']", "Receive stock")
      assert has_element?(lv, "a[href='/lab/receive-stock'] .bg-warning", "1")
    end

    test "shows no badge when there are no pending batches", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id, site_type: :lab})

      lab_tech =
        staff_fixture(%{
          organization_id: organization.id,
          role: :lab_technician,
          site_id: site.id
        })

      {:ok, lv, _html} = live(log_in_user(conn, lab_tech), ~p"/lab")

      refute has_element?(lv, "a[href='/lab/receive-stock'] .bg-warning")
    end
  end
end
