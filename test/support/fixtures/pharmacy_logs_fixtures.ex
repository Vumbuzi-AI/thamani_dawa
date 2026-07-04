defmodule ThamaniDawa.PharmacyLogsFixtures do
  @moduledoc """
  Test helpers for creating entities via `ThamaniDawa.PharmacyLogs`.
  """

  alias ThamaniDawa.OrganizationsFixtures
  alias ThamaniDawa.PharmacyLogs
  alias ThamaniDawa.SitesFixtures

  def valid_pharmacy_log_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      log_type: "cold_chain_temperature",
      month: 1,
      year: 2026
    })
  end

  @doc """
  Creates a pharmacy log. Unless given, `organization_id` gets a fresh
  organization, and `site_id` gets a fresh site under that organization.
  """
  def pharmacy_log_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn -> OrganizationsFixtures.organization_fixture().id end)

    {site_id, attrs} =
      Map.pop_lazy(attrs, :site_id, fn ->
        SitesFixtures.site_fixture(%{organization_id: organization_id}).id
      end)

    attrs = Map.merge(attrs, %{site_id: site_id})

    {:ok, pharmacy_log} =
      attrs
      |> valid_pharmacy_log_attributes()
      |> then(&PharmacyLogs.create_pharmacy_log(organization_id, &1))

    pharmacy_log
  end
end
