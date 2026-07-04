defmodule ThamaniDawa.LabTestsFixtures do
  @moduledoc """
  Test helpers for creating entities via `ThamaniDawa.LabTests`.
  """

  alias ThamaniDawa.LabTests
  alias ThamaniDawa.OrganizationsFixtures

  def valid_lab_test_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Full Blood Count #{System.unique_integer()}",
      price: Decimal.new("500.00")
    })
  end

  @doc "Creates a lab test under a fresh organization unless `organization_id` is given."
  def lab_test_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn ->
        OrganizationsFixtures.organization_fixture().id
      end)

    {:ok, lab_test} =
      attrs
      |> valid_lab_test_attributes()
      |> then(&LabTests.create_lab_test(organization_id, &1))

    lab_test
  end
end
