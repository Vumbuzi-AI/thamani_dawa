defmodule ThamaniDawa.LabTestsFixtures do
  @moduledoc """
  Test helpers for creating entities via `ThamaniDawa.LabTests`.
  """

  alias ThamaniDawa.LabTests
  alias ThamaniDawa.OrganizationsFixtures

  def valid_lab_test_category_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{name: "Haematology #{System.unique_integer()}"})
  end

  @doc "Creates a lab test category under a fresh organization unless `organization_id` is given."
  def lab_test_category_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn ->
        OrganizationsFixtures.organization_fixture().id
      end)

    {:ok, category} =
      attrs
      |> valid_lab_test_category_attributes()
      |> then(&LabTests.create_lab_test_category(organization_id, &1))

    category
  end

  def valid_lab_test_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Full Blood Count #{System.unique_integer()}",
      price: Decimal.new("500.00"),
      field_definitions: %{
        "haemoglobin" => %{"type" => "number", "unit" => "g/dL"}
      }
    })
  end

  @doc "Creates a lab test under a fresh organization unless `organization_id` is given."
  def lab_test_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn ->
        OrganizationsFixtures.organization_fixture().id
      end)

    {category_id, attrs} =
      Map.pop_lazy(attrs, :category_id, fn ->
        lab_test_category_fixture(%{organization_id: organization_id}).id
      end)

    attrs = Map.put(attrs, :category_id, category_id)

    {:ok, lab_test} =
      attrs
      |> valid_lab_test_attributes()
      |> then(&LabTests.create_lab_test(organization_id, &1))

    lab_test
  end
end
