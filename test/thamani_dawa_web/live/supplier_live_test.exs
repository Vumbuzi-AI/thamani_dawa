defmodule ThamaniDawaWeb.SupplierLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.SuppliersFixtures

  setup do
    %{admin: user_fixture()}
  end

  describe "index" do
    test "lists suppliers for the organization", %{conn: conn, admin: admin} do
      supplier =
        supplier_fixture(%{
          organization_id: admin.organization_id,
          name: "Acme Distributors"
        })

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/suppliers")

      assert html =~ supplier.name
      assert html =~ supplier.contact
      assert html =~ supplier.phone
      assert html =~ supplier.email
      assert html =~ supplier.gln
    end

    test "does not list another organization's suppliers", %{conn: conn, admin: admin} do
      other_org_supplier =
        supplier_fixture(%{organization_id: organization_fixture().id, name: "Hostile Supplier"})

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/suppliers")

      refute html =~ other_org_supplier.name
    end

    test "opens the add-supplier modal and closes it again on cancel", %{
      conn: conn,
      admin: admin
    } do
      {:ok, lv, html} = live(log_in_user(conn, admin), ~p"/org/suppliers")
      assert html =~ "+ Add supplier"
      refute has_element?(lv, "#supplier-modal")

      html = lv |> element("a", "+ Add supplier") |> render_click()

      assert has_element?(lv, "#supplier-modal")
      assert html =~ "Add a supplier"

      html = lv |> element("#supplier-modal button[aria-label='Cancel']") |> render_click()

      refute has_element?(lv, "#supplier-modal")
      assert html =~ "+ Add supplier"
    end

    test "creates a new supplier", %{conn: conn, admin: admin} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/suppliers")

      lv |> element("a", "+ Add supplier") |> render_click()

      lv
      |> form("#supplier-form",
        supplier: %{
          name: "New Supplier",
          contact: "Jane Doe",
          phone: "+254700000000",
          email: "jane@newsupplier.test",
          location: "Nairobi"
        }
      )
      |> render_submit()

      html = render(lv)
      assert html =~ "Supplier created."
      assert html =~ "New Supplier"
    end

    test "shows validation errors when required fields are missing", %{conn: conn, admin: admin} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/suppliers")

      lv |> element("a", "+ Add supplier") |> render_click()

      html =
        lv
        |> form("#supplier-form", supplier: %{name: "", phone: "", email: ""})
        |> render_change()

      assert html =~ "can&#39;t be blank"
    end

    test "shows an error and does not create a supplier with a malformed email", %{
      conn: conn,
      admin: admin
    } do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/suppliers")

      lv |> element("a", "+ Add supplier") |> render_click()

      html =
        lv
        |> form("#supplier-form",
          supplier: %{name: "New Supplier", phone: "+254700000000", email: "not-an-email"}
        )
        |> render_submit()

      assert html =~ "Please enter a valid email"

      refute Enum.any?(
               ThamaniDawa.Suppliers.list_suppliers(admin.organization_id),
               &(&1.name == "New Supplier")
             )
    end

    test "edits an existing supplier without duplicating it in the stream", %{
      conn: conn,
      admin: admin
    } do
      supplier =
        supplier_fixture(%{organization_id: admin.organization_id, name: "Old Name"})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/suppliers")

      lv |> element("#suppliers-#{supplier.id} a", "Edit") |> render_click()

      lv
      |> form("#supplier-form", supplier: %{name: "Updated Name"})
      |> render_submit()

      html = render(lv)
      assert html =~ "Supplier updated."
      assert html =~ "Updated Name"
      refute html =~ "Old Name"

      assert html |> String.split("id=\"suppliers-#{supplier.id}\"") |> length() == 2
    end

    test "shows an error and does not persist an invalid edit", %{conn: conn, admin: admin} do
      supplier = supplier_fixture(%{organization_id: admin.organization_id, name: "Keep Me"})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/suppliers")

      lv |> element("#suppliers-#{supplier.id} a", "Edit") |> render_click()

      html =
        lv
        |> form("#supplier-form", supplier: %{email: "not-an-email"})
        |> render_submit()

      assert html =~ "Please enter a valid email"

      assert %{name: "Keep Me"} =
               ThamaniDawa.Suppliers.get_supplier!(admin.organization_id, supplier.id)
    end

    test "cannot edit another organization's supplier via a direct URL", %{
      conn: conn,
      admin: admin
    } do
      other_org_supplier = supplier_fixture(%{organization_id: organization_fixture().id})

      assert_raise Ecto.NoResultsError, fn ->
        live(log_in_user(conn, admin), ~p"/org/suppliers/#{other_org_supplier.id}/edit")
      end
    end

    test "searches suppliers by name", %{conn: conn, admin: admin} do
      supplier_fixture(%{organization_id: admin.organization_id, name: "Acme Distributors"})
      supplier_fixture(%{organization_id: admin.organization_id, name: "BioLab East Africa"})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/suppliers")

      lv |> form("form[phx-change='search']", search: "acme") |> render_change()

      html = render(lv)
      assert html =~ "Acme Distributors"
      refute html =~ "BioLab East Africa"
    end
  end

  describe "active-state behavior" do
    test "deactivates an active supplier", %{conn: conn, admin: admin} do
      supplier = supplier_fixture(%{organization_id: admin.organization_id})
      assert supplier.is_active

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/suppliers")
      render_click(lv, "toggle_active", %{"id" => to_string(supplier.id)})

      assert %{is_active: false} =
               ThamaniDawa.Suppliers.get_supplier!(admin.organization_id, supplier.id)
    end

    test "reactivates an inactive supplier", %{conn: conn, admin: admin} do
      supplier = supplier_fixture(%{organization_id: admin.organization_id})
      {:ok, _} = ThamaniDawa.Suppliers.update_supplier(supplier, %{is_active: false})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/suppliers")
      render_click(lv, "toggle_active", %{"id" => to_string(supplier.id)})

      assert %{is_active: true} =
               ThamaniDawa.Suppliers.get_supplier!(admin.organization_id, supplier.id)
    end

    test "filters by active status", %{conn: conn, admin: admin} do
      active = supplier_fixture(%{organization_id: admin.organization_id, name: "Active Co"})
      inactive = supplier_fixture(%{organization_id: admin.organization_id, name: "Inactive Co"})
      {:ok, _} = ThamaniDawa.Suppliers.update_supplier(inactive, %{is_active: false})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/suppliers")

      lv
      |> form("#suppliers-filters-form", filters: %{status: "inactive"})
      |> render_submit()

      html = render(lv)
      assert html =~ inactive.name
      refute html =~ active.name
    end

    test "clear_filters resets the status filter", %{conn: conn, admin: admin} do
      active = supplier_fixture(%{organization_id: admin.organization_id, name: "Active Co"})
      inactive = supplier_fixture(%{organization_id: admin.organization_id, name: "Inactive Co"})
      {:ok, _} = ThamaniDawa.Suppliers.update_supplier(inactive, %{is_active: false})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/suppliers")

      lv
      |> form("#suppliers-filters-form", filters: %{status: "active"})
      |> render_submit()

      refute render(lv) =~ inactive.name

      lv |> element("button", "Clear filters") |> render_click()

      html = render(lv)
      assert html =~ active.name
      assert html =~ inactive.name
    end

    test "clearing the status filter chip removes just that filter", %{conn: conn, admin: admin} do
      active = supplier_fixture(%{organization_id: admin.organization_id, name: "Active Co"})
      inactive = supplier_fixture(%{organization_id: admin.organization_id, name: "Inactive Co"})
      {:ok, _} = ThamaniDawa.Suppliers.update_supplier(inactive, %{is_active: false})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/suppliers")

      lv
      |> form("#suppliers-filters-form", filters: %{status: "active"})
      |> render_submit()

      lv
      |> element("button[aria-label='Remove Status: Active filter']")
      |> render_click()

      html = render(lv)
      assert html =~ active.name
      assert html =~ inactive.name
    end
  end
end
