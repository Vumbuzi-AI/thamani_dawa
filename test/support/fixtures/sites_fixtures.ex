defmodule ThamaniDawa.SitesFixtures do
  @moduledoc """
  Test helpers for creating entities via `ThamaniDawa.Sites`.
  """

  alias ThamaniDawa.OrganizationsFixtures
  alias ThamaniDawa.Sites

  def valid_site_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Main Site #{System.unique_integer()}",
      site_type: :pharmacy,
      gln: "#{:rand.uniform(9_999_999_999_999) + 1_000_000_000_000}",
      address: "#{System.unique_integer([:positive])} Test Street"
    })
  end

  @doc "Creates a site under a fresh organization unless `organization_id` is given."
  def site_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn ->
        OrganizationsFixtures.organization_fixture().id
      end)

    {:ok, site} =
      attrs
      |> valid_site_attributes()
      |> then(&Sites.create_site(organization_id, &1))

    site
  end
end
