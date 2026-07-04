defmodule ThamaniDawa.OrganizationsFixtures do
  @moduledoc """
  Test helpers for creating entities via `ThamaniDawa.Organizations`.
  """

  def valid_organization_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Acme Pharmacy #{System.unique_integer()}"
    })
  end

  def organization_fixture(attrs \\ %{}) do
    {:ok, organization} =
      attrs
      |> valid_organization_attributes()
      |> ThamaniDawa.Organizations.create_organization()

    organization
  end
end
