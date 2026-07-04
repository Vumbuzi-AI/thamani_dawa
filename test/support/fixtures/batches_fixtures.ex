defmodule ThamaniDawa.BatchesFixtures do
  @moduledoc """
  Test helpers for creating entities via `ThamaniDawa.Batches`.
  """

  alias ThamaniDawa.Batches
  alias ThamaniDawa.OrganizationsFixtures
  alias ThamaniDawa.ProductsFixtures
  alias ThamaniDawa.SitesFixtures

  def valid_batch_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      gtin: unique_gtin(),
      batch_no: "BATCH-#{System.unique_integer()}",
      expiry: ~D[2027-01-01],
      quantity: 100
    })
  end

  @doc "Generates a fresh, GS1-checksum-valid GTIN-14 for test fixtures."
  def unique_gtin do
    base =
      System.unique_integer([:positive]) |> Integer.to_string() |> String.pad_leading(13, "0")

    {:ok, gtin} = ThamaniDawa.Gtin.generate(base)
    gtin
  end

  @doc """
  Creates a batch. Unless given, `organization_id` gets a fresh organization,
  and `product_id`/`site_id` get a fresh product/site under that organization.
  """
  def batch_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn ->
        OrganizationsFixtures.organization_fixture().id
      end)

    {product_id, attrs} =
      Map.pop_lazy(attrs, :product_id, fn ->
        ProductsFixtures.product_fixture(%{organization_id: organization_id}).id
      end)

    {site_id, attrs} =
      Map.pop_lazy(attrs, :site_id, fn ->
        SitesFixtures.site_fixture(%{organization_id: organization_id}).id
      end)

    attrs = Map.merge(attrs, %{product_id: product_id, site_id: site_id})

    {:ok, batch} =
      attrs
      |> valid_batch_attributes()
      |> then(&Batches.create_batch(organization_id, &1))

    batch
  end
end
