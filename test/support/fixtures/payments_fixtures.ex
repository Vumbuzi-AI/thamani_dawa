defmodule ThamaniDawa.PaymentsFixtures do
  @moduledoc """
  Test helpers for creating entities via `ThamaniDawa.Payments`.
  """

  alias ThamaniDawa.LabOrders.LabOrder
  alias ThamaniDawa.LabOrdersFixtures
  alias ThamaniDawa.OrganizationsFixtures
  alias ThamaniDawa.Payments
  alias ThamaniDawa.Prescriptions.PrescriptionItem
  alias ThamaniDawa.ProductsFixtures
  alias ThamaniDawa.Repo

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

    attrs = valid_payment_attributes(attrs)

    attrs =
      cond do
        attrs[:lab_order_id] ->
          case Repo.get(LabOrder, attrs.lab_order_id) do
            %LabOrder{} = lab_order ->
              _ = Repo.update!(Ecto.Changeset.change(lab_order, total_amount: attrs.amount))
              attrs

            nil ->
              attrs
          end

        attrs[:prescription_id] ->
          ensure_prescription_payable(organization_id, attrs.prescription_id, attrs.amount)
          attrs

        true ->
          lab_order =
            LabOrdersFixtures.lab_order_fixture(%{
              organization_id: organization_id,
              total_amount: attrs.amount
            })

          Map.put(attrs, :lab_order_id, lab_order.id)
      end

    {:ok, payment} =
      attrs
      |> then(&Payments.create_payment(organization_id, &1))

    payment
  end

  @doc """
  Makes `prescription_id` have a payable total of exactly `amount`, by
  giving it a dispensed item at that price. Bypasses the stock/site
  checks on `Prescriptions.create_prescription_item/3` — those are
  exercised by the dispensing tests, not these payment tests.
  """
  def ensure_prescription_payable(organization_id, prescription_id, amount) do
    product =
      ProductsFixtures.product_fixture(%{
        organization_id: organization_id,
        price: Decimal.to_integer(amount)
      })

    %PrescriptionItem{}
    |> PrescriptionItem.changeset(%{
      product_id: product.id,
      quantity_prescribed: 1,
      quantity_dispensed: 1
    })
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Ecto.Changeset.put_change(:prescription_id, prescription_id)
    |> Repo.insert!()
  end
end
