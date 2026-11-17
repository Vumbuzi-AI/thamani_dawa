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
      site = site_fixture(%{organization_id: org.id, activities: [:laboratory]})
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
    test "creates a requisition for the lab technician's own site", %{conn: conn} do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id, activities: [:laboratory]})
      product = product_fixture(%{organization_id: org.id})
      lab_tech = lab_tech_at_sites(org, [site])

      {:ok, lv, _html} = live(log_in_user(conn, lab_tech), ~p"/lab/requisitions/new")

      lv
      |> form("#add-item-form", %{
        "product_id" => product.id,
        "requested_quantity" => "12"
      })
      |> render_submit()

      lv
      |> form("#requisition-form", %{"site_id" => site.id})
      |> render_submit()

      assert_patch(lv, ~p"/lab/requisitions")
      assert render(lv) =~ "12"
    end

    test "auto-selects single lab site and renders read-only without a dropdown", %{conn: conn} do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id, activities: [:laboratory]})
      _other_lab = site_fixture(%{organization_id: org.id, activities: [:laboratory]})
      lab_tech = lab_tech_at_sites(org, [site])

      {:ok, lv, html} = live(log_in_user(conn, lab_tech), ~p"/lab/requisitions/new")

      assert html =~ site.name
      refute has_element?(lv, "select[name='site_id']")

      assert has_element?(
               lv,
               "input[type='hidden'][name='site_id'][value='#{site.id}']"
             )
    end

    test "renders dropdown limited to user's lab sites for multi-site staff", %{conn: conn} do
      org = organization_fixture()

      site_a =
        site_fixture(%{organization_id: org.id, activities: [:laboratory], name: "Alpha Lab"})

      site_b =
        site_fixture(%{organization_id: org.id, activities: [:laboratory], name: "Beta Lab"})

      _other_lab =
        site_fixture(%{organization_id: org.id, activities: [:laboratory], name: "Gamma Lab"})

      _pharmacy_site =
        site_fixture(%{organization_id: org.id, activities: [:pharmacy], name: "Delta Pharmacy"})

      lab_tech = lab_tech_at_sites(org, [site_a, site_b])

      {:ok, lv, html} = live(log_in_user(conn, lab_tech), ~p"/lab/requisitions/new")

      assert has_element?(lv, "select[name='site_id']")
      assert html =~ "Alpha Lab"
      assert html =~ "Beta Lab"
      refute html =~ "Gamma Lab"
      refute html =~ "Delta Pharmacy"
    end

    test "rejects submission for a site the user cannot act on", %{conn: conn} do
      org = organization_fixture()
      site_a = site_fixture(%{organization_id: org.id, activities: [:laboratory]})
      site_b = site_fixture(%{organization_id: org.id, activities: [:laboratory]})
      other_site = site_fixture(%{organization_id: org.id, activities: [:laboratory]})
      product = product_fixture(%{organization_id: org.id})
      lab_tech = lab_tech_at_sites(org, [site_a, site_b])

      {:ok, lv, _html} = live(log_in_user(conn, lab_tech), ~p"/lab/requisitions/new")

      lv
      |> form("#add-item-form", %{
        "product_id" => product.id,
        "requested_quantity" => "3"
      })
      |> render_submit()

      html =
        lv
        |> element("#requisition-form")
        |> render_submit(%{"site_id" => other_site.id})

      assert html =~ "Choose a valid site."
      assert has_element?(lv, "#new-requisition-modal")
    end
  end
end
