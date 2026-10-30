defmodule ThamaniDawaWeb.LabRequisitionLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.RequisitionsFixtures
  import ThamaniDawa.SitesFixtures

  defp lab_tech_at_sites(organization, sites) do
    staff_fixture(%{
      organization_id: organization.id,
      role: :lab_technician,
      site_ids: Enum.map(sites, & &1.id)
    })
  end

  describe "lab requisitions list" do
    test "shows a requisition raised for the lab technician's site", %{conn: conn} do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id, site_type: :lab})
      product = product_fixture(%{organization_id: org.id})
      lab_tech = lab_tech_at_sites(org, [site])

      requisition_fixture(%{
        organization_id: org.id,
        site_id: site.id,
        product_id: product.id,
        quantity: 5
      })

      {:ok, _lv, html} = live(log_in_user(conn, lab_tech), ~p"/lab/requisitions")

      assert html =~ product.generic_name
      assert html =~ "5"
    end
  end

  describe "new lab requisition" do
    test "auto-selects single lab site and renders read-only without a dropdown", %{conn: conn} do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id, site_type: :lab})
      _other_lab = site_fixture(%{organization_id: org.id, site_type: :lab})
      lab_tech = lab_tech_at_sites(org, [site])

      {:ok, lv, html} = live(log_in_user(conn, lab_tech), ~p"/lab/requisitions/new")

      assert html =~ site.name
      refute has_element?(lv, "select[name='requisition[site_id]']")

      assert has_element?(
               lv,
               "input[type='hidden'][name='requisition[site_id]'][value='#{site.id}']"
             )
    end

    test "renders dropdown limited to user's lab sites for multi-site staff", %{conn: conn} do
      org = organization_fixture()
      site_a = site_fixture(%{organization_id: org.id, site_type: :lab, name: "Alpha Lab"})
      site_b = site_fixture(%{organization_id: org.id, site_type: :lab, name: "Beta Lab"})
      _other_lab = site_fixture(%{organization_id: org.id, site_type: :lab, name: "Gamma Lab"})

      _pharmacy_site =
        site_fixture(%{organization_id: org.id, site_type: :pharmacy, name: "Delta Pharmacy"})

      lab_tech = lab_tech_at_sites(org, [site_a, site_b])

      {:ok, lv, html} = live(log_in_user(conn, lab_tech), ~p"/lab/requisitions/new")

      assert has_element?(lv, "select[name='requisition[site_id]']")
      assert html =~ "Alpha Lab"
      assert html =~ "Beta Lab"
      refute html =~ "Gamma Lab"
      refute html =~ "Delta Pharmacy"
    end

    test "rejects submission for a site the user cannot act on", %{conn: conn} do
      org = organization_fixture()
      site_a = site_fixture(%{organization_id: org.id, site_type: :lab})
      site_b = site_fixture(%{organization_id: org.id, site_type: :lab})
      other_site = site_fixture(%{organization_id: org.id, site_type: :lab})
      product = product_fixture(%{organization_id: org.id})
      lab_tech = lab_tech_at_sites(org, [site_a, site_b])

      {:ok, lv, _html} = live(log_in_user(conn, lab_tech), ~p"/lab/requisitions/new")

      html =
        lv
        |> element("#requisition-form")
        |> render_submit(%{
          "requisition" => %{
            "site_id" => other_site.id,
            "product_id" => product.id,
            "quantity" => "3"
          }
        })

      assert html =~ "is not a site you can act on"
      assert has_element?(lv, "#new-requisition-modal")
    end
  end
end
