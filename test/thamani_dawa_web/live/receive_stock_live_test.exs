defmodule ThamaniDawaWeb.ReceiveStockLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures

  alias ThamaniDawa.Batches

  defp pharmacist_at_site(organization, site) do
    staff_fixture(%{organization_id: organization.id, site_id: site.id})
  end

  describe "pending batches list" do
    test "shows a batch dispatched to the pharmacist's own site", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id, site_id: site.id})
      pharmacist = pharmacist_at_site(organization, site)

      batch =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          product_id: product.id,
          batch_no: "LOT-HERE",
          pending: true
        })

      {:ok, lv, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/receive-stock")

      assert html =~ "LOT-HERE"
      assert has_element?(lv, "#receive-batch-#{batch.id}")
    end

    test "does not show a batch dispatched to a different site", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      other_site = site_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id, site_id: site.id})
      pharmacist = pharmacist_at_site(organization, site)

      _batch =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: other_site.id,
          product_id: product.id,
          batch_no: "LOT-ELSEWHERE",
          pending: true
        })

      {:ok, _lv, html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/receive-stock")

      refute html =~ "LOT-ELSEWHERE"
    end
  end

  describe "manual receipt" do
    test "receiving a pending batch approves it and removes it from the list", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id, site_id: site.id})
      pharmacist = pharmacist_at_site(organization, site)

      batch =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          product_id: product.id,
          batch_no: "LOT-MANUAL",
          quantity: 100,
          pending: true
        })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/receive-stock")

      lv
      |> form("#receive-batch-#{batch.id}", %{"quantity" => "100"})
      |> render_submit()

      refute has_element?(lv, "#receive-batch-#{batch.id}")
      assert render(lv) =~ "Stock received."

      received = Batches.get_batch!(organization.id, batch.id)
      assert received.approver_id == pharmacist.id
      assert received.received_by_id == pharmacist.id
      assert %DateTime{} = received.received_at
    end

    test "an edited quantity on receipt becomes the batch's quantity and remaining_quantity", %{
      conn: conn
    } do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id, site_id: site.id})
      pharmacist = pharmacist_at_site(organization, site)

      batch =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          product_id: product.id,
          batch_no: "LOT-SHORT-SHIP",
          quantity: 100,
          pending: true
        })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/receive-stock")

      lv
      |> form("#receive-batch-#{batch.id}", %{"quantity" => "80"})
      |> render_submit()

      received = Batches.get_batch!(organization.id, batch.id)
      assert received.quantity == 80
      assert received.remaining_quantity == 80
    end
  end

  describe "GS1-assisted receipt" do
    test "a scanned code matching a pending batch's gtin and batch_no receives it", %{
      conn: conn
    } do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id, site_id: site.id})
      pharmacist = pharmacist_at_site(organization, site)
      gtin = unique_gtin()

      batch =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          product_id: product.id,
          gtin: gtin,
          batch_no: "LOT-GS1",
          pending: true
        })

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/receive-stock")

      lv
      |> form("#receive-stock-gs1-form", raw_gs1: "01" <> gtin <> "10" <> "LOT-GS1")
      |> render_submit()

      refute has_element?(lv, "#receive-batch-#{batch.id}")
      assert render(lv) =~ "Stock received."

      received = Batches.get_batch!(organization.id, batch.id)
      assert received.approver_id == pharmacist.id
    end

    test "invalid GS1 input shows a decode error", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/receive-stock")

      lv
      |> form("#receive-stock-gs1-form", raw_gs1: "01" <> "123")
      |> render_submit()

      assert has_element?(lv, "#gs1-decode-error", "Couldn't decode that code")
    end

    test "a well-formed code with no matching pending batch shows a not-found error", %{
      conn: conn
    } do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)
      gtin = unique_gtin()

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/receive-stock")

      lv
      |> form("#receive-stock-gs1-form", raw_gs1: "01" <> gtin <> "10" <> "NO-SUCH-LOT")
      |> render_submit()

      assert has_element?(lv, "#gs1-decode-error", "No matching pending batch at your site")
    end
  end
end
