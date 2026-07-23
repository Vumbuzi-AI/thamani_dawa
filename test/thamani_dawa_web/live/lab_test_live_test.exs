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

    test "clearing the category filter chip removes just that filter", %{
      conn: conn,
      admin: admin
    } do
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

      lv
      |> element("button[aria-label='Remove Category: Serology filter']")
      |> render_click()

      html = render(lv)
      assert html =~ "Widal Test"
      assert html =~ "Haemoglobin Panel"
    end

    test "clearing the status filter chip removes just that filter", %{conn: conn, admin: admin} do
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

      lv
      |> element("button[aria-label='Remove Status: Inactive filter']")
      |> render_click()

      html = render(lv)
      assert html =~ active.name
      assert html =~ inactive.name
    end

    test "filters by status: active", %{conn: conn, admin: admin} do
      active =
        lab_test_fixture(%{organization_id: admin.organization_id, name: "Active Test Alpha"})

      inactive =
        lab_test_fixture(%{organization_id: admin.organization_id, name: "Inactive Test Beta"})

      {:ok, _} =
        ThamaniDawa.LabTests.update_lab_test(admin.organization_id, inactive, %{is_active: false})

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/lab/tests")

      lv
      |> form("#lab-tests-filters-form", filters: %{status: "active"})
      |> render_submit()

      html = render(lv)
      assert html =~ active.name
      refute html =~ inactive.name
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

    test "clear_filters resets category and status filters", %{conn: conn, admin: admin} do
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

      refute render(lv) =~ "Haemoglobin Panel"

      lv |> element("button", "Clear filters") |> render_click()

      html = render(lv)
      assert html =~ "Haemoglobin Panel"
      assert html =~ "Widal Test"
    end
  end

  describe "create test" do
    test "renders the form when navigating to /lab/tests/new", %{conn: conn, admin: admin} do
      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/new")
      assert has_element?(view, "#lab-test-form")
    end

    test "creates a test and streams it into the table", %{conn: conn, admin: admin} do
      category = lab_test_category_fixture(%{organization_id: admin.organization_id})
      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/new")

      view
      |> form("#lab-test-form", %{
        "lab_test" => %{
          "name" => "Haemoglobin",
          "category_id" => to_string(category.id),
          "price" => "350.00",
          "is_active" => "true"
        },
        "field_defs_json" => ~s({"hb": {"type": "number", "unit": "g/dL"}})
      })
      |> render_submit()

      assert_patch(view, ~p"/lab/tests")
      assert render(view) =~ "Haemoglobin"
    end

    test "creates a test with an inline new category", %{conn: conn, admin: admin} do
      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/new")

      view |> element("button[phx-click=toggle_new_category]") |> render_click()

      view
      |> form("#lab-test-form", %{
        "lab_test" => %{
          "name" => "Haemoglobin",
          "price" => "350.00",
          "is_active" => "true"
        },
        "category" => %{"name" => "New Category #{System.unique_integer()}"},
        "field_defs_json" => ~s({"hb": {"type": "number", "unit": "g/dL"}})
      })
      |> render_submit()

      assert_patch(view, ~p"/lab/tests")
      assert render(view) =~ "Haemoglobin"
    end

    test "shows an error and does not save when the inline new category name is blank", %{
      conn: conn,
      admin: admin
    } do
      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/new")

      view |> element("button[phx-click=toggle_new_category]") |> render_click()

      html =
        view
        |> form("#lab-test-form", %{
          "lab_test" => %{"name" => "Some Test", "price" => "100.00"},
          "category" => %{"name" => ""},
          "field_defs_json" => ~s({"x": {"type": "string"}})
        })
        |> render_submit()

      assert html =~ "can&#39;t be blank"

      refute Enum.any?(
               ThamaniDawa.LabTests.list_lab_tests(admin.organization_id),
               &(&1.name == "Some Test")
             )
    end

    test "shows validation errors when name is blank", %{conn: conn, admin: admin} do
      category = lab_test_category_fixture(%{organization_id: admin.organization_id})
      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/new")

      html =
        view
        |> form("#lab-test-form", %{
          "lab_test" => %{"name" => "", "category_id" => to_string(category.id)},
          "field_defs_json" => ~s({"x": {"type": "string"}})
        })
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end
  end

  describe "field-definition presets" do
    test "the category field is a dropdown, not free text", %{conn: conn, admin: admin} do
      lab_test_category_fixture(%{organization_id: admin.organization_id})
      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/new")

      assert has_element?(view, "select[name='lab_test[category_id]']")
    end

    test "selecting a preset fills name, category, and field definitions", %{
      conn: conn,
      admin: admin
    } do
      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/new")

      html =
        view
        |> form("#lab-test-preset-form", preset: "Complete Blood Count")
        |> render_change()

      assert html =~ "haemoglobin"
      assert html =~ "Hematology"

      view
      |> form("#lab-test-form", %{"lab_test" => %{"price" => "800.00"}})
      |> render_submit()

      assert_patch(view, ~p"/lab/tests")

      [saved] = ThamaniDawa.LabTests.list_lab_tests(admin.organization_id)
      assert saved.name == "Complete Blood Count"
      assert saved.field_definitions["haemoglobin"]["unit"] == "g/dL"

      category =
        ThamaniDawa.LabTests.get_lab_test_category!(admin.organization_id, saved.category_id)

      assert category.name == "Hematology"
    end

    test "fields already typed before picking a preset are preserved (e.g. price)", %{
      conn: conn,
      admin: admin
    } do
      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/new")

      view
      |> form("#lab-test-form", %{"lab_test" => %{"price" => "450.00"}})
      |> render_change()

      html =
        view
        |> form("#lab-test-preset-form", preset: "HIV Rapid Test")
        |> render_change()

      assert html =~ "450.00"

      view
      |> form("#lab-test-form", %{})
      |> render_submit()

      assert_patch(view, ~p"/lab/tests")

      [saved] = ThamaniDawa.LabTests.list_lab_tests(admin.organization_id)
      assert saved.name == "HIV Rapid Test"
      assert Decimal.equal?(saved.price, Decimal.new("450.00"))
    end

    test "picking a preset reuses an existing matching category instead of duplicating it", %{
      conn: conn,
      admin: admin
    } do
      lab_test_category_fixture(%{organization_id: admin.organization_id, name: "Hematology"})
      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/new")

      view
      |> form("#lab-test-preset-form", preset: "Complete Blood Count")
      |> render_change()

      categories = ThamaniDawa.LabTests.list_lab_test_categories(admin.organization_id)
      assert Enum.count(categories, &(&1.name == "Hematology")) == 1
    end

    test "an already-edited field-definitions value is preserved when a preset is picked", %{
      conn: conn,
      admin: admin
    } do
      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/new")

      view
      |> form("#lab-test-form", %{
        "lab_test" => %{"name" => "My Custom Test"},
        "field_defs_json" => ~s({"custom_field":{"type":"text"}})
      })
      |> render_change()

      html =
        view
        |> form("#lab-test-preset-form", preset: "Malaria Parasite")
        |> render_change()

      assert html =~ "custom_field"
      refute html =~ "parasites"
      assert html =~ "already edited"
    end

    test "picking a preset while editing an existing test preserves its saved field definitions",
         %{conn: conn, admin: admin} do
      lab_test =
        lab_test_fixture(%{organization_id: admin.organization_id, name: "Existing Test"})

      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/#{lab_test.id}/edit")

      html =
        view
        |> form("#lab-test-preset-form", preset: "Malaria Parasite")
        |> render_change()

      assert html =~ "Malaria Parasite"
      assert html =~ "haemoglobin"
      refute html =~ "parasites"
      assert html =~ "already edited"
    end

    test "clearing the preset selection doesn't touch whatever was already applied", %{
      conn: conn,
      admin: admin
    } do
      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/new")

      view
      |> form("#lab-test-preset-form", preset: "Complete Blood Count")
      |> render_change()

      html =
        view
        |> form("#lab-test-preset-form", preset: "")
        |> render_change()

      assert html =~ "Complete Blood Count"
      assert html =~ "haemoglobin"
    end

    test "an unrecognized preset name is ignored instead of crashing", %{conn: conn, admin: admin} do
      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/new")

      html = render_change(view, "select_preset", %{"preset" => "Not A Real Preset"})

      assert html =~ "New test"
      refute html =~ "haemoglobin"
    end

    test "a category-creation race shows an error instead of crashing", %{
      conn: conn,
      admin: admin
    } do
      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/new")

      # Simulate another process creating the same category after this view's own category
      # list was already loaded — the view can't see it and will try to create it again.
      {:ok, _category} =
        ThamaniDawa.LabTests.create_lab_test_category(admin.organization_id, %{
          name: "Hematology"
        })

      html =
        view
        |> form("#lab-test-preset-form", preset: "Complete Blood Count")
        |> render_change()

      assert html =~ "apply that preset"
    end
  end

  describe "invalid field-definitions JSON" do
    test "shows an error and does not save when field_defs_json is invalid", %{
      conn: conn,
      admin: admin
    } do
      category = lab_test_category_fixture(%{organization_id: admin.organization_id})
      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/new")

      html =
        view
        |> form("#lab-test-form", %{
          "lab_test" => %{
            "name" => "Bad JSON Test",
            "category_id" => to_string(category.id),
            "price" => "100"
          },
          "field_defs_json" => "not json"
        })
        |> render_submit()

      assert html =~ "must be valid JSON"

      refute Enum.any?(
               ThamaniDawa.LabTests.list_lab_tests(admin.organization_id),
               &(&1.name == "Bad JSON Test")
             )
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

    test "shows an error and does not persist an invalid edit", %{conn: conn, admin: admin} do
      lab_test =
        lab_test_fixture(%{organization_id: admin.organization_id, name: "Keep Me"})

      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/#{lab_test.id}/edit")

      html =
        view
        |> form("#lab-test-form", %{
          "lab_test" => %{"name" => ""},
          "field_defs_json" => Jason.encode!(lab_test.field_definitions)
        })
        |> render_submit()

      assert html =~ "can&#39;t be blank"

      assert %{name: "Keep Me"} =
               ThamaniDawa.LabTests.get_lab_test!(admin.organization_id, lab_test.id)
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
