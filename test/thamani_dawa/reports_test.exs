defmodule ThamaniDawa.ReportsTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Payments
  alias ThamaniDawa.Reports

  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.LabOrdersFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.PaymentsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures
  import ThamaniDawa.SuppliersFixtures

  describe "expiring_batches/2" do
    test "lists batches with stock expiring within the window, soonest first, across every site" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id})
      supplier = supplier_fixture(%{organization_id: organization.id})

      soon =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          product_id: product.id,
          supplier_id: supplier.id,
          expiry_date: Date.add(Date.utc_today(), 5)
        })

      later =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          product_id: product.id,
          expiry_date: Date.add(Date.utc_today(), 20)
        })

      _far_off =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          product_id: product.id,
          expiry_date: Date.add(Date.utc_today(), 365)
        })

      assert [first, second] = Reports.expiring_batches(organization.id, 30)
      assert first.id == soon.id
      assert second.id == later.id
      assert first.product.id == product.id
      assert first.site.id == site.id
      assert first.supplier.id == supplier.id
    end

    test "excludes batches with no stock remaining" do
      organization = organization_fixture()

      depleted =
        batch_fixture(%{
          organization_id: organization.id,
          expiry_date: Date.add(Date.utc_today(), 5),
          quantity: 10
        })

      {:ok, _} = ThamaniDawa.Batches.decrement_remaining_quantity(depleted, 10)

      assert Reports.expiring_batches(organization.id, 30) == []
    end
  end

  describe "site_profitability/1" do
    test "nets revenue against cost of goods dispensed, per site" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})

      lab_order = lab_order_fixture(%{organization_id: organization.id, site_id: site.id})

      {:ok, _} =
        Payments.complete_payment(
          payment_fixture(%{
            organization_id: organization.id,
            lab_order_id: lab_order.id,
            amount: Decimal.new("500")
          })
        )

      batch =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          cost_per_unit: Decimal.new("10.00")
        })

      technician =
        ThamaniDawa.AccountsFixtures.staff_fixture(%{
          organization_id: organization.id,
          role: :lab_technician
        })

      {:ok, _usage} =
        ThamaniDawa.LabOrders.record_consumable_usage(
          organization.id,
          batch.id,
          technician.id,
          5
        )

      assert [row] =
               organization.id
               |> Reports.site_profitability()
               |> Enum.filter(&(&1.site.id == site.id))

      assert Decimal.equal?(row.revenue, Decimal.new("500"))
      assert Decimal.equal?(row.cost_of_goods, Decimal.new("50.00"))
      assert Decimal.equal?(row.profit, Decimal.new("450.00"))
    end

    test "includes every site even with zero activity" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})

      assert [row] = Reports.site_profitability(organization.id)
      assert row.site.id == site.id
      assert Decimal.equal?(row.revenue, Decimal.new(0))
      assert Decimal.equal?(row.cost_of_goods, Decimal.new(0))
      assert Decimal.equal?(row.profit, Decimal.new(0))
    end
  end
end
