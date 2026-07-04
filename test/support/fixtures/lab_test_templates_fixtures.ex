defmodule ThamaniDawa.LabTestTemplatesFixtures do
  @moduledoc """
  Test helpers for creating entities via `ThamaniDawa.LabTestTemplates`.
  """

  alias ThamaniDawa.LabTestTemplates
  alias ThamaniDawa.OrganizationsFixtures

  def valid_lab_test_category_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{name: "Haematology #{System.unique_integer()}"})
  end

  def valid_lab_test_template_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Full Blood Count #{System.unique_integer()}",
      short_name: "FBC",
      field_definitions: [
        %{key: "wbc", label: "White Blood Cells", unit: "x10^9/L", low: 4.0, high: 11.0},
        %{key: "hgb", label: "Haemoglobin", unit: "g/dL", low: 13.0, high: 17.0}
      ]
    })
  end

  @doc "Creates a lab test category under a fresh organization unless `organization_id` is given."
  def lab_test_category_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn -> OrganizationsFixtures.organization_fixture().id end)

    {:ok, category} =
      attrs
      |> valid_lab_test_category_attributes()
      |> then(&LabTestTemplates.create_lab_test_category(organization_id, &1))

    category
  end

  @doc "Creates a lab test template under a fresh organization unless `organization_id` is given."
  def lab_test_template_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn -> OrganizationsFixtures.organization_fixture().id end)

    {:ok, template} =
      attrs
      |> valid_lab_test_template_attributes()
      |> then(&LabTestTemplates.create_lab_test_template(organization_id, &1))

    template
  end
end
