defmodule ThamaniDawaWeb.RequisitionLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.RequisitionsFixtures
  import ThamaniDawa.SitesFixtures

  defp pharmacist_at_site(organization, site) do
    staff_fixture(%{organization_id: organization.id, site_id: site.id})
  end

  describe "requisitions list" do
    test "shows a requisition raised by the pharmacist's own site", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)

      requisition_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        quantity: 7
      })

      {:ok, _lv, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/requisitions")

      assert html =~ product.generic_name
      assert html =~ "7"
    end

    test "does not show a requisition raised by a different site", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      other_site = site_fixture(%{organization_id: organization.id})

      product =
        product_fixture(%{organization_id: organization.id, generic_name: "Elsewhere Drug"})

      pharmacist = pharmacist_at_site(organization, site)

      requisition_fixture(%{
        organization_id: organization.id,
        site_id: other_site.id,
        product_id: product.id
      })

      {:ok, _lv, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/requisitions")

      refute html =~ "Elsewhere Drug"
    end
  end

  describe "new requisition" do
    test "creates a requisition for the pharmacist's own site", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/requisitions/new")

      lv
      |> form("#requisition-form",
        requisition: %{"site_id" => site.id, "product_id" => product.id, "quantity" => "12"}
      )
      |> render_submit()

      assert_patch(lv, ~p"/pharmacy/requisitions")
      assert render(lv) =~ "12"
    end

    test "auto-selects single site and renders read-only without a dropdown", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      _other_site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)

      {:ok, lv, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/requisitions/new")

      assert html =~ site.name
      refute has_element?(lv, "select[name='requisition[site_id]']")

      assert has_element?(
               lv,
               "input[type='hidden'][name='requisition[site_id]'][value='#{site.id}']"
             )
    end

    test "renders dropdown limited to user sites for multi-site staff", %{conn: conn} do
      organization = organization_fixture()
      site_a = site_fixture(%{organization_id: organization.id, name: "Alpha Pharmacy"})
      site_b = site_fixture(%{organization_id: organization.id, name: "Beta Pharmacy"})
      _other_site = site_fixture(%{organization_id: organization.id, name: "Gamma Org Pharmacy"})

      pharmacist =
        staff_fixture(%{organization_id: organization.id, site_ids: [site_a.id, site_b.id]})

      {:ok, lv, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/requisitions/new")

      assert has_element?(lv, "select[name='requisition[site_id]']")
      assert html =~ "Alpha Pharmacy"
      assert html =~ "Beta Pharmacy"
      refute html =~ "Gamma Org Pharmacy"
    end

    test "rejects submission for a site the user cannot act on", %{conn: conn} do
      organization = organization_fixture()
      site_a = site_fixture(%{organization_id: organization.id})
      site_b = site_fixture(%{organization_id: organization.id})
      other_site = site_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id})

      pharmacist =
        staff_fixture(%{organization_id: organization.id, site_ids: [site_a.id, site_b.id]})

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/requisitions/new")

      html =
        lv
        |> element("#requisition-form")
        |> render_submit(%{
          "requisition" => %{
            "site_id" => other_site.id,
            "product_id" => product.id,
            "quantity" => "5"
          }
        })

      assert html =~ "is not a site you can act on"
      assert has_element?(lv, "#new-requisition-modal")
    end
  end
end
