defmodule ThamaniDawa.OrganizationsFixtures do
  @moduledoc """
  Test helpers for creating entities via `ThamaniDawa.Organizations`.
  """

  def valid_organization_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Acme Pharmacy #{System.unique_integer([:positive])}",
      license_number: "LIC-#{System.unique_integer([:positive])}",
      operating_models: [:pharmacy]
    })
  end

  def organization_fixture(attrs \\ %{}) do
    {:ok, organization} =
      attrs
      |> valid_organization_attributes()
      |> ThamaniDawa.Organizations.create_organization()

    organization
  end

  @doc "Creates an organization with a GS1 company prefix already set."
  def organization_with_prefix_fixture(attrs \\ %{}, prefix \\ "0614141") do
    organization = organization_fixture(Enum.into(attrs, %{operating_models: [:distributor]}))

    {:ok, organization} =
      ThamaniDawa.Organizations.update_organization_gs1_settings(
        organization,
        %{gs1_company_prefix: prefix}
      )

    organization
  end
end
