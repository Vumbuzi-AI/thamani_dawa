defmodule ThamaniDawa.SuppliersFixtures do
  @moduledoc """
  Test helpers for creating entities via `ThamaniDawa.Suppliers`.
  """

  alias ThamaniDawa.OrganizationsFixtures
  alias ThamaniDawa.Suppliers

  def valid_supplier_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Acme Distributors #{System.unique_integer()}"
    })
  end

  @doc "Creates a supplier under a fresh organization unless `organization_id` is given."
  def supplier_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn ->
        OrganizationsFixtures.organization_fixture().id
      end)

    {:ok, supplier} =
      attrs
      |> valid_supplier_attributes()
      |> then(&Suppliers.create_supplier(organization_id, &1))

    supplier
  end
end
