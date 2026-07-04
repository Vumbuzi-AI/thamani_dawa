defmodule ThamaniDawa.LabTestTemplatesTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.LabTestTemplates
  alias ThamaniDawa.LabTestTemplates.{LabTestCategory, LabTestTemplate}

  import ThamaniDawa.LabTestTemplatesFixtures
  import ThamaniDawa.OrganizationsFixtures

  describe "create_lab_test_category/2" do
    test "requires name" do
      organization = organization_fixture()

      assert {:error, changeset} = LabTestTemplates.create_lab_test_category(organization.id, %{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "enforces uniqueness of (organization_id, name)" do
      organization = organization_fixture()
      lab_test_category_fixture(%{organization_id: organization.id, name: "Haematology"})

      assert {:error, changeset} =
               LabTestTemplates.create_lab_test_category(organization.id, %{name: "Haematology"})

      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end

    test "the same name is allowed across different organizations" do
      organization_a = organization_fixture()
      organization_b = organization_fixture()
      lab_test_category_fixture(%{organization_id: organization_a.id, name: "Haematology"})

      assert {:ok, %LabTestCategory{}} =
               LabTestTemplates.create_lab_test_category(organization_b.id, %{name: "Haematology"})
    end
  end

  describe "create_lab_test_template/2" do
    test "requires name" do
      organization = organization_fixture()

      assert {:error, changeset} = LabTestTemplates.create_lab_test_template(organization.id, %{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "enforces uniqueness of (organization_id, name)" do
      organization = organization_fixture()
      lab_test_template_fixture(%{organization_id: organization.id, name: "Full Blood Count"})

      assert {:error, changeset} =
               LabTestTemplates.create_lab_test_template(organization.id, %{
                 name: "Full Blood Count"
               })

      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end

    test "casts field_definitions into embedded structs" do
      organization = organization_fixture()

      assert {:ok, %LabTestTemplate{field_definitions: [wbc, hgb]}} =
               LabTestTemplates.create_lab_test_template(organization.id, %{
                 name: "Full Blood Count",
                 field_definitions: [
                   %{key: "wbc", label: "White Blood Cells", low: 4.0, high: 11.0},
                   %{key: "hgb", label: "Haemoglobin", low: 13.0, high: 17.0}
                 ]
               })

      assert wbc.key == "wbc"
      assert wbc.low == 4.0
      assert hgb.key == "hgb"
    end
  end

  describe "compute_results/2" do
    test "flags a numeric value below the reference range as low" do
      template = lab_test_template_fixture()

      assert %{"wbc" => %{"value" => 2.0, "flag" => "low"}} =
               LabTestTemplates.compute_results(template, %{"wbc" => 2.0})
    end

    test "flags a numeric value above the reference range as high" do
      template = lab_test_template_fixture()

      assert %{"wbc" => %{"value" => 20.0, "flag" => "high"}} =
               LabTestTemplates.compute_results(template, %{"wbc" => 20.0})
    end

    test "flags a numeric value within the reference range as normal" do
      template = lab_test_template_fixture()

      assert %{"wbc" => %{"value" => 7.0, "flag" => "normal"}} =
               LabTestTemplates.compute_results(template, %{"wbc" => 7.0})
    end

    test "parses numeric strings the same as floats" do
      template = lab_test_template_fixture()

      assert %{"wbc" => %{"value" => "20.0", "flag" => "high"}} =
               LabTestTemplates.compute_results(template, %{"wbc" => "20.0"})
    end

    test "leaves the flag nil for a field with no matching definition" do
      template = lab_test_template_fixture()

      assert %{"unknown_field" => %{"value" => "x", "flag" => nil}} =
               LabTestTemplates.compute_results(template, %{"unknown_field" => "x"})
    end

    test "accepts atom keys and always returns string keys" do
      template = lab_test_template_fixture()

      assert %{"wbc" => %{"flag" => "normal"}} =
               LabTestTemplates.compute_results(template, %{wbc: 7.0})
    end
  end
end
