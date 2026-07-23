defmodule ThamaniDawa.PrescriptionsFixtures do
  @moduledoc """
  Test helpers for creating entities via `ThamaniDawa.Prescriptions`.
  """

  alias ThamaniDawa.OrganizationsFixtures
  alias ThamaniDawa.PatientVisitsFixtures
  alias ThamaniDawa.Prescriptions
  alias ThamaniDawa.ProductsFixtures

  def valid_prescription_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      doctors_note: "Take after meals",
      source_facility: "General Hospital",
      referring_doctor: "Dr. Jane Doe",
      referral_date: ~D[2026-01-15],
      payment_type: "Cash"
    })
  end

  def valid_prescription_item_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{quantity_prescribed: 10})
  end

  @doc """
  Creates a prescription. Unless given, `organization_id` gets a fresh
  organization, and `patient_visit_id` gets a fresh visit under that
  organization.
  """
  def prescription_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn ->
        OrganizationsFixtures.organization_fixture().id
      end)

    {patient_visit_id, attrs} =
      Map.pop_lazy(attrs, :patient_visit_id, fn ->
        PatientVisitsFixtures.patient_visit_fixture(%{organization_id: organization_id}).id
      end)

    attrs = Map.put(attrs, :patient_visit_id, patient_visit_id)

    {:ok, prescription} =
      attrs
      |> valid_prescription_attributes()
      |> then(&Prescriptions.create_prescription(organization_id, &1))

    prescription
  end

  @doc """
  Creates a prescription item. Unless given, `organization_id`/
  `prescription_id` get a fresh organization/prescription, and `product_id`
  gets a fresh product under that organization.
  """
  def prescription_item_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn ->
        OrganizationsFixtures.organization_fixture().id
      end)

    {prescription_id, attrs} =
      Map.pop_lazy(attrs, :prescription_id, fn ->
        prescription_fixture(%{organization_id: organization_id}).id
      end)

    {product_id, attrs} =
      Map.pop_lazy(attrs, :product_id, fn ->
        ProductsFixtures.product_fixture(%{organization_id: organization_id}).id
      end)

    attrs = Map.merge(attrs, %{product_id: product_id})

    {:ok, item} =
      attrs
      |> valid_prescription_item_attributes()
      |> then(&Prescriptions.create_prescription_item(organization_id, prescription_id, &1))

    item
  end
end
