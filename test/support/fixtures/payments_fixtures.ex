defmodule ThamaniDawa.PaymentsFixtures do
  @moduledoc """
  Test helpers for creating entities via `ThamaniDawa.Payments`.
  """

  alias ThamaniDawa.LabOrdersFixtures
  alias ThamaniDawa.OrganizationsFixtures
  alias ThamaniDawa.Payments

  def valid_payment_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      amount: Decimal.new("500"),
      payment_type: "Cash"
    })
  end

  @doc """
  Creates a payment. Unless given, `organization_id` gets a fresh
  organization, and — unless a `prescription_id` or `lab_order_id` is
  given — a fresh lab order under that organization is used as the
  payment's order.
  """
  def payment_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn ->
        OrganizationsFixtures.organization_fixture().id
      end)

    attrs =
      if Map.has_key?(attrs, :prescription_id) or Map.has_key?(attrs, :lab_order_id) do
        attrs
      else
        lab_order = LabOrdersFixtures.lab_order_fixture(%{organization_id: organization_id})
        Map.put(attrs, :lab_order_id, lab_order.id)
      end

    {:ok, payment} =
      attrs
      |> valid_payment_attributes()
      |> then(&Payments.create_payment(organization_id, &1))

    payment
  end
end
