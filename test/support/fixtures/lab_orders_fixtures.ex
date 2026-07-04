defmodule ThamaniDawa.LabOrdersFixtures do
  @moduledoc """
  Test helpers for creating entities via `ThamaniDawa.LabOrders`.
  """

  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.LabTestsFixtures
  alias ThamaniDawa.OrganizationsFixtures
  alias ThamaniDawa.PatientsFixtures
  alias ThamaniDawa.SitesFixtures

  def valid_lab_order_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{prescriber_name: "Dr. Jane Doe"})
  end

  def valid_lab_order_test_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{})
  end

  @doc """
  Creates a lab order. Unless given, `organization_id` gets a fresh
  organization, and `site_id`/`patient_id` get a fresh site/patient under
  that organization.
  """
  def lab_order_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn -> OrganizationsFixtures.organization_fixture().id end)

    {site_id, attrs} =
      Map.pop_lazy(attrs, :site_id, fn ->
        SitesFixtures.site_fixture(%{organization_id: organization_id}).id
      end)

    {patient_id, attrs} =
      Map.pop_lazy(attrs, :patient_id, fn ->
        PatientsFixtures.patient_fixture(%{organization_id: organization_id}).id
      end)

    attrs = Map.merge(attrs, %{site_id: site_id, patient_id: patient_id})

    {:ok, lab_order} =
      attrs
      |> valid_lab_order_attributes()
      |> then(&LabOrders.create_lab_order(organization_id, &1))

    lab_order
  end

  @doc """
  Creates a lab order test. Unless given, `organization_id`/`lab_order_id`
  get a fresh organization/lab order, and `lab_test_id` gets a fresh lab
  test under that organization.
  """
  def lab_order_test_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn -> OrganizationsFixtures.organization_fixture().id end)

    {lab_order_id, attrs} =
      Map.pop_lazy(attrs, :lab_order_id, fn ->
        lab_order_fixture(%{organization_id: organization_id}).id
      end)

    {lab_test_id, attrs} =
      Map.pop_lazy(attrs, :lab_test_id, fn ->
        LabTestsFixtures.lab_test_fixture(%{organization_id: organization_id}).id
      end)

    attrs = Map.merge(attrs, %{lab_test_id: lab_test_id})

    {:ok, lab_order_test} =
      attrs
      |> valid_lab_order_test_attributes()
      |> then(&LabOrders.create_lab_order_test(organization_id, lab_order_id, &1))

    lab_order_test
  end
end
