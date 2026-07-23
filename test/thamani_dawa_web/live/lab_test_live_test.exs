defmodule ThamaniDawaWeb.LabTestLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.LabTestsFixtures

  setup do
    admin = user_fixture()

    lab_tech =
      staff_fixture(%{
        organization_id: admin.organization_id,
        invited_by_id: admin.id,
        role: :lab_technician
      })

    %{admin: admin, lab_tech: lab_tech}
  end

  describe "catalog index" do
    test "admin sees active and inactive tests", %{conn: conn, admin: admin} do
      active =
        lab_test_fixture(%{organization_id: admin.organization_id, name: "Active Test Alpha"})

      inactive =
        lab_test_fixture(%{organization_id: admin.organization_id, name: "Inactive Test Beta"})

      {:ok, _} =
        ThamaniDawa.LabTests.update_lab_test(admin.organization_id, inactive, %{is_active: false})

      {:ok, _view, html} = live(log_in_user(conn, admin), ~p"/lab/tests")

      assert html =~ active.name
      assert html =~ inactive.name
    end

    test "lab technician can access the catalog", %{conn: conn, lab_tech: lab_tech} do
      lab_test_fixture(%{organization_id: lab_tech.organization_id})

      {:ok, _view, html} = live(log_in_user(conn, lab_tech), ~p"/lab/tests")
      assert html =~ "Test catalog"
    end

    test "searches by name", %{conn: conn, admin: admin} do
      lab_test_fixture(%{organization_id: admin.organization_id, name: "Haemoglobin Panel"})
      lab_test_fixture(%{organization_id: admin.organization_id, name: "Widal Test"})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/lab/tests")

      lv |> form("form[phx-change='search']", search: "haemoglobin") |> render_change()

      html = render(lv)
      assert html =~ "Haemoglobin Panel"
      refute html =~ "Widal Test"
    end

    test "filters by category", %{conn: conn, admin: admin} do
      lab_test_fixture(%{
        organization_id: admin.organization_id,
        name: "Haemoglobin Panel",
        category: "Haematology"
      })

      lab_test_fixture(%{
        organization_id: admin.organization_id,
        name: "Widal Test",
        category: "Serology"
      })

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/lab/tests")

      lv
      |> form("#lab-tests-filters-form", filters: %{category: "Serology"})
      |> render_submit()

      html = render(lv)
      assert html =~ "Widal Test"
      refute html =~ "Haemoglobin Panel"
      assert html =~ "Category: Serology"
    end

    test "filters by status", %{conn: conn, admin: admin} do
      active =
        lab_test_fixture(%{organization_id: admin.organization_id, name: "Active Test Alpha"})

      inactive =
        lab_test_fixture(%{organization_id: admin.organization_id, name: "Inactive Test Beta"})

      {:ok, _} =
        ThamaniDawa.LabTests.update_lab_test(admin.organization_id, inactive, %{is_active: false})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/lab/tests")

      lv
      |> form("#lab-tests-filters-form", filters: %{status: "inactive"})
      |> render_submit()

      html = render(lv)
      assert html =~ inactive.name
      refute html =~ active.name
    end
  end

  describe "create test" do
    test "renders the form when navigating to /lab/tests/new", %{conn: conn, admin: admin} do
      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/new")
      assert has_element?(view, "#lab-test-form")
    end

    test "creates a test and streams it into the table", %{conn: conn, admin: admin} do
      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/new")

      view
      |> form("#lab-test-form", %{
        "lab_test" => %{
          "name" => "Haemoglobin",
          "category" => "Haematology",
          "price" => "350.00",
          "is_active" => "true"
        },
        "field_defs_json" => ~s({"hb": {"type": "number", "unit": "g/dL"}})
      })
      |> render_submit()

      assert_patch(view, ~p"/lab/tests")
      assert render(view) =~ "Haemoglobin"
    end

    test "shows validation errors when name is blank", %{conn: conn, admin: admin} do
      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/new")

      html =
        view
        |> form("#lab-test-form", %{
          "lab_test" => %{"name" => "", "category" => "Haematology"},
          "field_defs_json" => ~s({"x": {"type": "string"}})
        })
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end
  end

  describe "edit test" do
    test "pre-populates the form with existing values", %{conn: conn, admin: admin} do
      lab_test =
        lab_test_fixture(%{organization_id: admin.organization_id, name: "Malaria RDT"})

      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/#{lab_test.id}/edit")

      assert has_element?(view, "#lab-test-form")
      assert render(view) =~ "Malaria RDT"
    end

    test "updates the test and reflects the change in the table", %{conn: conn, admin: admin} do
      lab_test =
        lab_test_fixture(%{organization_id: admin.organization_id, name: "Old Name"})

      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/#{lab_test.id}/edit")

      view
      |> form("#lab-test-form", %{
        "lab_test" => %{"name" => "New Name"},
        "field_defs_json" => Jason.encode!(lab_test.field_definitions)
      })
      |> render_submit()

      assert_patch(view, ~p"/lab/tests")
      assert render(view) =~ "New Name"
      refute render(view) =~ "Old Name"
    end
  end

  describe "deactivate and reactivate" do
    test "toggle_active flips is_active from true to false", %{conn: conn, admin: admin} do
      lab_test = lab_test_fixture(%{organization_id: admin.organization_id})
      assert lab_test.is_active == true

      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests")
      render_click(view, "toggle_active", %{"id" => to_string(lab_test.id)})

      assert %{is_active: false} =
               ThamaniDawa.LabTests.get_lab_test!(admin.organization_id, lab_test.id)
    end

    test "toggle_active flips is_active from false to true", %{conn: conn, admin: admin} do
      lab_test = lab_test_fixture(%{organization_id: admin.organization_id})

      {:ok, inactive} =
        ThamaniDawa.LabTests.update_lab_test(admin.organization_id, lab_test, %{is_active: false})

      assert inactive.is_active == false

      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests")
      render_click(view, "toggle_active", %{"id" => to_string(lab_test.id)})

      assert %{is_active: true} =
               ThamaniDawa.LabTests.get_lab_test!(admin.organization_id, lab_test.id)
    end
  end

  describe "inactive hidden from new order" do
    test "inactive tests do not appear in order test selection", %{conn: conn, admin: admin} do
      active = lab_test_fixture(%{organization_id: admin.organization_id, name: "Active CBC"})

      inactive =
        lab_test_fixture(%{organization_id: admin.organization_id, name: "Inactive Lipids"})

      {:ok, _} =
        ThamaniDawa.LabTests.update_lab_test(admin.organization_id, inactive, %{is_active: false})

      {:ok, _view, html} = live(log_in_user(conn, admin), ~p"/lab/orders/new")

      assert html =~ active.name
      refute html =~ inactive.name
    end
  end
end
