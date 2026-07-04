defmodule ThamaniDawa.DangerousDrugRegistersFixtures do
  @moduledoc """
  Test helpers for creating entities via `ThamaniDawa.DangerousDrugRegisters`.
  """

  alias ThamaniDawa.DangerousDrugRegisters
  alias ThamaniDawa.OrganizationsFixtures
  alias ThamaniDawa.ProductsFixtures
  alias ThamaniDawa.SitesFixtures

  def valid_dangerous_drug_register_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{month: 1, year: 2026})
  end

  @doc """
  Creates a dangerous drug register. Unless given, `organization_id` gets a
  fresh organization, and `site_id`/`product_id` get a fresh site/product
  under that organization.
  """
  def dangerous_drug_register_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn ->
        OrganizationsFixtures.organization_fixture().id
      end)

    {site_id, attrs} =
      Map.pop_lazy(attrs, :site_id, fn ->
        SitesFixtures.site_fixture(%{organization_id: organization_id}).id
      end)

    {product_id, attrs} =
      Map.pop_lazy(attrs, :product_id, fn ->
        ProductsFixtures.product_fixture(%{organization_id: organization_id}).id
      end)

    attrs = Map.merge(attrs, %{site_id: site_id, product_id: product_id})

    {:ok, register} =
      attrs
      |> valid_dangerous_drug_register_attributes()
      |> then(&DangerousDrugRegisters.create_dangerous_drug_register(organization_id, &1))

    register
  end
end
