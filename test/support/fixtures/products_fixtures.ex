defmodule ThamaniDawa.ProductsFixtures do
  @moduledoc """
  Test helpers for creating entities via `ThamaniDawa.Products`.
  """

  alias ThamaniDawa.OrganizationsFixtures
  alias ThamaniDawa.Products

  def valid_product_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      generic_name: "Paracetamol #{System.unique_integer()}",
      product_type: :drug,
      uom: "tablet"
    })
  end

  @doc "Creates a product under a fresh organization unless `organization_id` is given."
  def product_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn -> OrganizationsFixtures.organization_fixture().id end)

    {:ok, product} =
      attrs
      |> valid_product_attributes()
      |> then(&Products.create_product(organization_id, &1))

    product
  end
end
