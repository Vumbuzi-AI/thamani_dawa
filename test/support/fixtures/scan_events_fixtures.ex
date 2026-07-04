defmodule ThamaniDawa.ScanEventsFixtures do
  @moduledoc """
  Test helpers for creating entities via `ThamaniDawa.ScanEvents`.
  """

  alias ThamaniDawa.BatchesFixtures
  alias ThamaniDawa.OrganizationsFixtures
  alias ThamaniDawa.ScanEvents

  def valid_scan_event_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      gtin: BatchesFixtures.unique_gtin(),
      batch_no: "BATCH-#{System.unique_integer()}",
      event_type: :dispense
    })
  end

  @doc """
  Creates a scan event. Unless given, `organization_id` gets a fresh
  organization.
  """
  def scan_event_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn ->
        OrganizationsFixtures.organization_fixture().id
      end)

    {:ok, scan_event} =
      attrs
      |> valid_scan_event_attributes()
      |> then(&ScanEvents.create_scan_event(organization_id, &1))

    scan_event
  end
end
