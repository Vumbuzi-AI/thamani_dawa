defmodule ThamaniDawaWeb.RequisitionQueueLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.RequisitionsFixtures
  import ThamaniDawa.SitesFixtures

  describe "requisitions queue" do
    test "shows requisitions across every site in the organization", %{conn: conn} do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      site_a = site_fixture(%{organization_id: organization.id})
      site_b = site_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id})

      requisition_fixture(%{
        organization_id: organization.id,
        site_id: site_a.id,
        product_id: product.id
      })

      requisition_fixture(%{
        organization_id: organization.id,
        site_id: site_b.id,
        product_id: product.id
      })

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/requisitions")

      assert html =~ site_a.name
      assert html =~ site_b.name
    end
  end

  describe "approve" do
    test "approving a pending requisition flips its status", %{conn: conn} do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      requisition = requisition_fixture(%{organization_id: organization.id})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/requisitions")

      lv
      |> element("button[phx-click='approve'][phx-value-id='#{requisition.id}']")
      |> render_click()

      assert render(lv) =~ "Approved"
    end
  end

  describe "reject" do
    test "rejecting requires a reason and updates status", %{conn: conn} do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      requisition = requisition_fixture(%{organization_id: organization.id})

      {:ok, lv, _html} =
        live(log_in_user(conn, admin), ~p"/org/requisitions/#{requisition.id}/reject")

      lv
      |> form("#reject-form", reject: %{"rejection_reason" => "No budget"})
      |> render_submit()

      assert_patch(lv, ~p"/org/requisitions")
      assert render(lv) =~ "Rejected"
    end
  end

  describe "fulfill" do
    test "shows the needs_reorder banner and dispatches stock from the chosen batch", %{
      conn: conn
    } do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id})

      org_batch =
        org_batch_fixture(%{
          organization_id: organization.id,
          product_id: product.id,
          quantity: 20
        })

      requisition =
        requisition_fixture(%{
          organization_id: organization.id,
          product_id: product.id,
          quantity: 10
        })

      {:ok, approved} =
        ThamaniDawa.Requisitions.approve_requisition(organization.id, requisition.id, admin.id)

      refute approved.needs_reorder

      {:ok, lv, _html} =
        live(log_in_user(conn, admin), ~p"/org/requisitions/#{requisition.id}/fulfill")

      lv
      |> form("#fulfill-form", fulfill: %{"org_batch_id" => org_batch.id, "quantity" => "10"})
      |> render_submit()

      assert_patch(lv, ~p"/org/requisitions")
      assert render(lv) =~ "Fulfilled"
    end
  end
end
