defmodule ThamaniDawaWeb.PharmacyScanLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures

  defp pharmacist_at(organization, site) do
    staff_fixture(%{organization_id: organization.id, site_id: site.id})
  end

  describe "initial mount" do
    test "shows the idle hint before any scan", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at(organization, site)

      {:ok, lv, _html} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/scan")

      assert has_element?(lv, "#scan-idle-hint")
      refute has_element?(lv, "#scan-result-found")
      refute has_element?(lv, "#scan-result-unavailable")
      refute has_element?(lv, "#scan-result-not-at-site")
    end
  end

  describe "approved batch at own site" do
    setup do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      gtin = unique_gtin()

      product =
        product_fixture(%{
          organization_id: organization.id,
          generic_name: "Amoxicillin 500mg",
          gtin: gtin
        })

      batch =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          product_id: product.id,
          gtin: gtin,
          batch_no: "LOT-APPROVED",
          expiry_date: ~D[2028-06-30],
          quantity: 200,
          remaining_quantity: 200
        })

      pharmacist = pharmacist_at(organization, site)

      %{
        organization: organization,
        site: site,
        product: product,
        batch: batch,
        gtin: gtin,
        pharmacist: pharmacist
      }
    end

    test "shows the found card with product name", %{conn: conn, pharmacist: p, gtin: gtin} do
      {:ok, lv, _} = live(log_in_user(conn, p), ~p"/pharmacy/scan")
      lv |> form("#scan-form", gtin: gtin) |> render_submit()

      assert has_element?(lv, "#scan-result-found")
      assert has_element?(lv, "#result-product-name", "Amoxicillin 500mg")
    end

    test "shows GTIN", %{conn: conn, pharmacist: p, gtin: gtin} do
      {:ok, lv, _} = live(log_in_user(conn, p), ~p"/pharmacy/scan")
      lv |> form("#scan-form", gtin: gtin) |> render_submit()

      assert has_element?(lv, "#result-gtin", gtin)
    end

    test "shows batch/lot number for a single batch", %{conn: conn, pharmacist: p, gtin: gtin} do
      {:ok, lv, _} = live(log_in_user(conn, p), ~p"/pharmacy/scan")
      lv |> form("#scan-form", gtin: gtin) |> render_submit()

      assert has_element?(lv, "#result-batch-no", "LOT-APPROVED")
    end

    test "aggregates batches when multiple exist", %{
      conn: conn,
      pharmacist: p,
      gtin: gtin,
      organization: org,
      site: site,
      product: product
    } do
      # Add a second batch
      batch_fixture(%{
        organization_id: org.id,
        site_id: site.id,
        product_id: product.id,
        gtin: gtin,
        batch_no: "LOT-APPROVED-2",
        expiry_date: ~D[2028-01-01],
        quantity: 150,
        remaining_quantity: 150
      })

      {:ok, lv, _} = live(log_in_user(conn, p), ~p"/pharmacy/scan")
      lv |> form("#scan-form", gtin: gtin) |> render_submit()

      # Should show total quantity (200 + 150 = 350)
      assert has_element?(lv, "#result-quantity", "350")
      # Should show earliest expiry (Jan 1, 2028)
      assert has_element?(lv, "#result-expiry", "01 Jan 2028")
      assert has_element?(lv, "#result-expiry", "(Earliest)")
      # Should show "2 batches" instead of a single lot
      assert has_element?(lv, "#result-batch-no", "2 batches")
    end

    test "shows expiry date", %{conn: conn, pharmacist: p, gtin: gtin} do
      {:ok, lv, _} = live(log_in_user(conn, p), ~p"/pharmacy/scan")
      lv |> form("#scan-form", gtin: gtin) |> render_submit()

      assert has_element?(lv, "#result-expiry", "30 Jun 2028")
    end

    test "shows site name", %{conn: conn, pharmacist: p, gtin: gtin, site: site} do
      {:ok, lv, _} = live(log_in_user(conn, p), ~p"/pharmacy/scan")
      lv |> form("#scan-form", gtin: gtin) |> render_submit()

      assert has_element?(lv, "#result-site", site.name)
    end

    test "shows remaining quantity", %{conn: conn, pharmacist: p, gtin: gtin, batch: batch} do
      {:ok, lv, _} = live(log_in_user(conn, p), ~p"/pharmacy/scan")
      lv |> form("#scan-form", gtin: gtin) |> render_submit()

      assert has_element?(lv, "#result-quantity", to_string(batch.remaining_quantity))
    end

    test "does not show unavailable or not-at-site cards on a match", %{
      conn: conn,
      pharmacist: p,
      gtin: gtin
    } do
      {:ok, lv, _} = live(log_in_user(conn, p), ~p"/pharmacy/scan")
      lv |> form("#scan-form", gtin: gtin) |> render_submit()

      refute has_element?(lv, "#scan-result-unavailable")
      refute has_element?(lv, "#scan-result-not-at-site")
      refute has_element?(lv, "#scan-idle-hint")
    end
  end

  describe "approved batch at a different site" do
    test "shows the not-at-site card, not the found card", %{conn: conn} do
      organization = organization_fixture()
      site_a = site_fixture(%{organization_id: organization.id})
      site_b = site_fixture(%{organization_id: organization.id})
      gtin = unique_gtin()

      product = product_fixture(%{organization_id: organization.id, gtin: gtin})

      _batch =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: site_b.id,
          product_id: product.id,
          gtin: gtin,
          batch_no: "LOT-OTHER-SITE"
        })

      pharmacist_a = pharmacist_at(organization, site_a)

      {:ok, lv, _} = live(log_in_user(conn, pharmacist_a), ~p"/pharmacy/scan")
      lv |> form("#scan-form", gtin: gtin) |> render_submit()

      assert has_element?(lv, "#scan-result-not-at-site")
      assert has_element?(lv, "#scan-not-at-site-heading", "Not at your site")
      refute has_element?(lv, "#scan-result-found")
      refute has_element?(lv, "#scan-result-unavailable")
    end
  end

  describe "pending/unapproved batch" do
    test "shows the unavailable state, not the found card", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      gtin = unique_gtin()

      product = product_fixture(%{organization_id: organization.id, gtin: gtin})

      _batch =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          product_id: product.id,
          gtin: gtin,
          batch_no: "LOT-PENDING",
          pending: true
        })

      pharmacist = pharmacist_at(organization, site)

      {:ok, lv, _} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/scan")
      lv |> form("#scan-form", gtin: gtin) |> render_submit()

      assert has_element?(lv, "#scan-result-unavailable")
      assert has_element?(lv, "#scan-unavailable-heading", "No approved stock found")
      refute has_element?(lv, "#scan-result-found")
      refute has_element?(lv, "#scan-result-not-at-site")
    end
  end

  describe "batch not found" do
    test "shows unavailable when the GTIN doesn't match anything", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at(organization, site)

      {:ok, lv, _} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/scan")
      lv |> form("#scan-form", gtin: "NO-SUCH-GTIN") |> render_submit()

      assert has_element?(lv, "#scan-result-unavailable")
      refute has_element?(lv, "#scan-result-found")
      refute has_element?(lv, "#scan-result-not-at-site")
    end

    test "does not leak an approved batch belonging to a different organisation", %{conn: conn} do
      org_a = organization_fixture()
      org_b = organization_fixture()
      site_a = site_fixture(%{organization_id: org_a.id})
      site_b = site_fixture(%{organization_id: org_b.id})
      gtin = unique_gtin()

      product_b = product_fixture(%{organization_id: org_b.id, gtin: gtin})

      _batch_b =
        batch_fixture(%{
          organization_id: org_b.id,
          site_id: site_b.id,
          product_id: product_b.id,
          gtin: gtin,
          batch_no: "LOT-ORG-B"
        })

      pharmacist_a = pharmacist_at(org_a, site_a)

      {:ok, lv, _} = live(log_in_user(conn, pharmacist_a), ~p"/pharmacy/scan")
      lv |> form("#scan-form", gtin: gtin) |> render_submit()

      assert has_element?(lv, "#scan-result-unavailable")
      refute has_element?(lv, "#scan-result-found")
    end
  end

  describe "invalid input" do
    test "an empty code shows a decode error and stays idle", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at(organization, site)

      {:ok, lv, _} = live(log_in_user(conn, pharmacist), ~p"/pharmacy/scan")
      lv |> form("#scan-form", gtin: "") |> render_submit()

      assert has_element?(lv, "#scan-decode-error", "Please enter a valid GTIN.")
      refute has_element?(lv, "#scan-result-found")
      refute has_element?(lv, "#scan-result-unavailable")
      refute has_element?(lv, "#scan-result-not-at-site")
    end
  end
end
