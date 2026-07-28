defmodule ThamaniDawaWeb.LabTestLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.LabTestsFixtures

  setup do
    admin = staff_fixture(%{role: :admin})
    lab_tech = staff_fixture(%{role: :lab_technician, organization_id: admin.organization_id})

    pharmacist =
      staff_fixture(%{role: :pharmacist, organization_id: admin.organization_id})

    %{admin: admin, lab_tech: lab_tech, pharmacist: pharmacist}
  end

  describe "access control" do
    test "admins can access the catalog", %{conn: conn, admin: admin} do
      {:ok, _view, html} = live(log_in_user(conn, admin), ~p"/lab/tests")
      assert html =~ "Catalog"
    end

    test "lab technicians can access the catalog", %{conn: conn, lab_tech: lab_tech} do
      {:ok, _view, html} = live(log_in_user(conn, lab_tech), ~p"/lab/tests")
      assert html =~ "Catalog"
    end

    test "pharma_lab staff can access the catalog", %{conn: conn, admin: admin} do
      lab_site =
        ThamaniDawa.SitesFixtures.site_fixture(%{
          organization_id: admin.organization_id,
          type: :pharmacy_lab
        })

      pharma_lab =
        staff_fixture(%{
          role: :pharma_lab,
          organization_id: admin.organization_id,
          sites: [lab_site]
        })

      {:ok, _view, html} = live(log_in_user(conn, pharma_lab), ~p"/lab/tests")
      assert html =~ "Catalog"
    end

    test "pharmacists without lab access are redirected", %{
      conn: conn,
      pharmacist: pharmacist
    } do
      result = live(log_in_user(conn, pharmacist), ~p"/lab/tests")

      assert {:error, {:redirect, %{to: "/pharmacy"}}} = result
    end
  end

  describe "scoping" do
    test "users see tests from their organization only", %{conn: conn, admin: admin} do
      other_admin = staff_fixture(%{role: :admin})

      mine = lab_test_fixture(%{organization_id: admin.organization_id, name: "Mine"})
      theirs = lab_test_fixture(%{organization_id: other_admin.organization_id, name: "Theirs"})

      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests")

      assert has_element?(view, "#lab-tests", mine.name)
      refute has_element?(view, "#lab-tests", theirs.name)
    end
  end

  describe "listing and filtering" do
    test "shows tests with their category name, price, and active status", %{
      conn: conn,
      admin: admin
    } do
      category =
        lab_test_category_fixture(%{
          organization_id: admin.organization_id,
          name: "Haematology"
        })

      test =
        lab_test_fixture(%{
          organization_id: admin.organization_id,
          category_id: category.id,
          name: "Full Blood Count",
          price: Decimal.new("500.00"),
          is_active: true
        })

      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests")

      assert has_element?(view, "#lab-tests", test.name)
      assert has_element?(view, "#lab-tests", "Haematology")
      assert has_element?(view, "#lab-tests", "KES 500.00")
      assert has_element?(view, "#lab-tests", "Active")
    end

    test "search filters tests by name or category", %{conn: conn, admin: admin} do
      cat =
        lab_test_category_fixture(%{
          organization_id: admin.organization_id,
          name: "Serology"
        })

      malaria =
        lab_test_fixture(%{
          organization_id: admin.organization_id,
          category_id: cat.id,
          name: "Malaria RDT"
        })

      hiv =
        lab_test_fixture(%{
          organization_id: admin.organization_id,
          category_id: cat.id,
          name: "HIV Rapid"
        })

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/lab/tests")

      lv |> form("form[phx-change='search']", search: "malaria") |> render_change()
      assert render(lv) =~ malaria.name
      refute render(lv) =~ hiv.name
    end

    test "filtering by category", %{conn: conn, admin: admin} do
      cat1 =
        lab_test_category_fixture(%{organization_id: admin.organization_id, name: "Cat A"})

      cat2 =
        lab_test_category_fixture(%{organization_id: admin.organization_id, name: "Cat B"})

      test1 =
        lab_test_fixture(%{
          organization_id: admin.organization_id,
          category_id: cat1.id,
          name: "Test A"
        })

      test2 =
        lab_test_fixture(%{
          organization_id: admin.organization_id,
          category_id: cat2.id,
          name: "Test B"
        })

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/lab/tests")

      lv
      |> form("#catalog-filters-form", filters: %{category: "Cat A"})
      |> render_submit()

      assert render(lv) =~ test1.name
      refute render(lv) =~ test2.name
    end

    test "clearing filter chips", %{conn: conn, admin: admin} do
      cat = lab_test_category_fixture(%{organization_id: admin.organization_id, name: "Cat X"})

      test =
        lab_test_fixture(%{
          organization_id: admin.organization_id,
          category_id: cat.id,
          name: "Test X"
        })

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/lab/tests")

      lv
      |> form("#catalog-filters-form", filters: %{category: "Cat X"})
      |> render_submit()

      assert render(lv) =~ test.name

      lv |> element("button[aria-label='Remove Category: Cat X filter']") |> render_click()

      assert render(lv) =~ test.name
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
        "field_defs" => %{"0" => %{"key" => "hb", "type" => "number", "unit" => "g/dL"}}
      })
      |> render_submit()

      assert_patch(view, ~p"/lab/tests")
      assert render(view) =~ "Haemoglobin"
    end

    test "shows validation errors when name is blank", %{conn: conn, admin: admin} do
      category = lab_test_category_fixture(%{organization_id: admin.organization_id})
      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/new")

      html =
        view
        |> form("#lab-test-form", %{
          "lab_test" => %{"name" => "", "category_id" => to_string(category.id)},
          "field_defs" => %{"0" => %{"key" => "x", "type" => "text", "unit" => ""}}
        })
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end
  end

  describe "field-definition presets" do
    test "the category field is a dropdown, not free text", %{conn: conn, admin: admin} do
      lab_test_category_fixture(%{organization_id: admin.organization_id})

      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/new")

      assert has_element?(view, "#lab-test-form select[name='lab_test[category_id]']")
      refute has_element?(view, "#lab-test-form input[name='lab_test[category_id]']")
    end

    test "selecting a preset auto-fills category and field definitions", %{
      conn: conn,
      admin: admin
    } do
      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/new")

      html =
        view
        |> form("#lab-test-preset-form", preset: "Complete Blood Count")
        |> render_change()

      assert html =~ "Complete Blood Count"
      assert html =~ "haemoglobin"
    end

    test "selecting a preset creates the preset's category if it doesn't exist yet", %{
      conn: conn,
      admin: admin
    } do
      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/new")

      view
      |> form("#lab-test-preset-form", preset: "Complete Blood Count")
      |> render_change()

      categories = ThamaniDawa.LabTests.list_lab_test_categories(admin.organization_id)
      assert Enum.count(categories, &(&1.name == "Hematology")) == 1
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
  end

  describe "invalid field-definitions" do
    test "shows an error and does not save when a field row is missing a name", %{
      conn: conn,
      admin: admin
    } do
      category = lab_test_category_fixture(%{organization_id: admin.organization_id})
      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests/new")

      html =
        view
        |> form("#lab-test-form", %{
          "lab_test" => %{
            "name" => "Bad Field Test",
            "category_id" => to_string(category.id),
            "price" => "100"
          },
          "field_defs" => %{"0" => %{"key" => "", "type" => "number", "unit" => "g/dL"}}
        })
        |> render_submit()

      assert html =~ "Give every field a name."

      refute Enum.any?(
               ThamaniDawa.LabTests.list_lab_tests(admin.organization_id),
               &(&1.name == "Bad Field Test")
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
        "field_defs" => %{"0" => %{"key" => "haemoglobin", "type" => "number", "unit" => "g/dL"}}
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
          "field_defs" => %{
            "0" => %{"key" => "haemoglobin", "type" => "number", "unit" => "g/dL"}
          }
        })
        |> render_submit()

      assert html =~ "can&#39;t be blank"

      assert %{name: "Keep Me"} =
               ThamaniDawa.LabTests.get_lab_test!(admin.organization_id, lab_test.id)
    end
  end

  describe "deactivate and reactivate" do
    test "toggle_active flips is_active from true to false", %{conn: conn, admin: admin} do
      lab_test =
        lab_test_fixture(%{
          organization_id: admin.organization_id,
          name: "Deactivate Me",
          is_active: true
        })

      {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/lab/tests")

      view |> element("#btn-toggle-test-#{lab_test.id}") |> render_click()

      refute ThamaniDawa.LabTests.get_lab_test!(admin.organization_id, lab_test.id).is_active
    end
  end
end
