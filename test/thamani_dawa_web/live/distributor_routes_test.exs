defmodule ThamaniDawaWeb.DistributorRoutesTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures

  alias ThamaniDawa.ProductsFixtures
  alias ThamaniDawa.SitesFixtures

  alias ThamaniDawaWeb.UserAuth

  describe "GET /distributor" do
    test "a distributor can access the portal", %{conn: conn} do
      distributor = staff_fixture(%{role: :distributor})
      conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(distributor)

      assert {:ok, view, _html} = live(conn, ~p"/distributor")
      assert has_element?(view, "#sidebar-shell")
      assert has_element?(view, ".dashboard-stat-grid")
      refute has_element?(view, "#distributor-near-expiry-batches")
      refute has_element?(view, "#distributor-awaiting-dispatch")
    end

    test "an admin is redirected away", %{conn: conn} do
      admin = user_fixture()
      conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(admin)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/distributor")
    end

    test "a pharmacist is redirected away", %{conn: conn} do
      pharmacist = staff_fixture(%{role: :pharmacist})
      conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(pharmacist)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/distributor")
    end

    test "an anonymous visitor is redirected away", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/distributor")
    end
  end

  describe "GET /distributor/customers" do
    test "a distributor can manage customers", %{conn: conn} do
      distributor = staff_fixture(%{role: :distributor})
      conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(distributor)

      assert {:ok, view, _html} = live(conn, ~p"/distributor/customers")
      assert has_element?(view, "#distributor-customers")
      assert has_element?(view, "#add-distributor-customer")
    end
  end

  describe "GET /distributor/warehouses" do
    test "a distributor can manage warehouses", %{conn: conn} do
      distributor = staff_fixture(%{role: :distributor})
      conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(distributor)

      assert {:ok, view, _html} = live(conn, ~p"/distributor/warehouses")
      assert has_element?(view, "#add-distributor-warehouse")
      assert has_element?(view, "#distributor-warehouses")
    end
  end

  describe "GET /distributor/products" do
    test "a distributor can manage products", %{conn: conn} do
      distributor = staff_fixture(%{role: :distributor})
      conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(distributor)

      assert {:ok, view, _html} = live(conn, ~p"/distributor/products")
      assert has_element?(view, "#add-distributor-product")
      assert has_element?(view, "#distributor-products")
    end
  end

  describe "GET /distributor/receiving" do
    test "a distributor can access warehouse receiving", %{conn: conn} do
      distributor = staff_fixture(%{role: :distributor})
      conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(distributor)

      assert {:ok, view, _html} = live(conn, ~p"/distributor/receiving")
      assert has_element?(view, "#receive-distributor-stock")
      assert has_element?(view, "#distributor-receipts")
    end

    test "a valid GTIN selects its catalog product", %{conn: conn} do
      distributor = staff_fixture(%{role: :distributor})
      product = ProductsFixtures.product_fixture(%{organization_id: distributor.organization_id})

      _warehouse =
        SitesFixtures.site_fixture(%{
          organization_id: distributor.organization_id,
          site_type: :warehouse
        })

      conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(distributor)

      assert {:ok, view, _html} = live(conn, ~p"/distributor/receiving/new")

      view
      |> form("#distributor-scan-gtin-form", scan: %{gtin: product.gtin <> " "})
      |> render_change()

      assert has_element?(view, "#distributor-receipt-form")

      assert has_element?(
               view,
               "#distributor-receipt-form input[name='batch[gtin]'][value='#{product.gtin}']"
             )
    end

    test "an invalid GTIN keeps receiving open and reports a validation error", %{conn: conn} do
      distributor = staff_fixture(%{role: :distributor})
      conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(distributor)

      assert {:ok, view, _html} = live(conn, ~p"/distributor/receiving/new")

      view
      |> form("#distributor-scan-gtin-form", scan: %{gtin: "06160001000014"})
      |> render_change()

      assert has_element?(view, "#distributor-scan-error", "Enter or scan a valid GTIN.")
      assert has_element?(view, "#distributor-scan-gtin-form")
    end
  end

  describe "GET /distributor/shipments" do
    test "a distributor can access shipment history", %{conn: conn} do
      distributor = staff_fixture(%{role: :distributor})
      conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(distributor)

      assert {:ok, view, _html} = live(conn, ~p"/distributor/shipments")
      assert has_element?(view, "#distributor-shipments")
    end
  end

  describe "GET /distributor/suppliers" do
    test "a distributor can manage suppliers", %{conn: conn} do
      distributor = staff_fixture(%{role: :distributor})
      conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(distributor)

      assert {:ok, view, _html} = live(conn, ~p"/distributor/suppliers")
      assert has_element?(view, "#add-distributor-supplier")
      assert has_element?(view, "#distributor-suppliers")
    end
  end
end
