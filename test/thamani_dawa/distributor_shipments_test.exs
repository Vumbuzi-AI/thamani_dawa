defmodule ThamaniDawa.DistributorShipmentsTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.DistributorOrders
  alias ThamaniDawa.DistributorShipments
  alias ThamaniDawa.DistributorShipments.{Carton, ShipmentLine}
  alias ThamaniDawa.Repo

  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.DistributorFixtures
  import ThamaniDawa.ProductsFixtures

  setup do
    org = organization_with_gs1()
    warehouse = warehouse_fixture(org.id)
    customer = customer_fixture(org.id)
    product_a = product_fixture(%{organization_id: org.id, price: 500})
    product_b = product_fixture(%{organization_id: org.id, price: 200})

    batch_a =
      batch_fixture(%{
        organization_id: org.id,
        product_id: product_a.id,
        site_id: warehouse.id,
        quantity: 100
      })

    %{
      org: org,
      warehouse: warehouse,
      customer: customer,
      product_a: product_a,
      product_b: product_b,
      batch_a: batch_a
    }
  end

  describe "allocate_order/3" do
    test "fully allocates an order when sufficient stock exists", %{
      org: org,
      warehouse: warehouse,
      customer: customer,
      product_a: product_a,
      batch_a: batch_a
    } do
      order = order_fixture(org.id, customer.id, [{product_a.id, 40, 500}])

      assert {:ok, {shipment, carton}} =
               DistributorShipments.allocate_order(org.id, order, warehouse.id)

      assert shipment.status == "allocated"
      assert shipment.dispatched_at == nil
      assert shipment.order_id == order.id

      assert carton.sscc != nil
      assert String.length(carton.sscc) == 18

      reloaded = DistributorOrders.get_order!(org.id, order.id)
      assert reloaded.status == :allocated

      [item] = reloaded.items
      assert item.quantity_allocated == 40

      updated_batch = Repo.get!(ThamaniDawa.Batches.Batch, batch_a.id)
      assert updated_batch.remaining_quantity == 60

      lines =
        Repo.all(from l in ShipmentLine, where: l.shipment_id == ^shipment.id)

      assert length(lines) == 1
      assert hd(lines).quantity == 40
    end

    test "partially allocates when available stock is less than ordered", %{
      org: org,
      warehouse: warehouse,
      customer: customer,
      product_a: product_a,
      batch_a: batch_a
    } do
      order = order_fixture(org.id, customer.id, [{product_a.id, 150, 500}])

      assert {:ok, {_shipment, _carton}} =
               DistributorShipments.allocate_order(org.id, order, warehouse.id)

      reloaded = DistributorOrders.get_order!(org.id, order.id)
      assert reloaded.status == :allocated

      [item] = reloaded.items
      assert item.quantity_allocated == 100
      assert item.quantity == 150

      updated_batch = Repo.get!(ThamaniDawa.Batches.Batch, batch_a.id)
      assert updated_batch.remaining_quantity == 0
    end

    test "allocates 0 for an item with no stock without failing the whole order", %{
      org: org,
      warehouse: warehouse,
      customer: customer,
      product_a: product_a,
      product_b: product_b,
      batch_a: batch_a
    } do
      order =
        order_fixture(org.id, customer.id, [
          {product_a.id, 30, 500},
          {product_b.id, 50, 200}
        ])

      assert {:ok, {shipment, _carton}} =
               DistributorShipments.allocate_order(org.id, order, warehouse.id)

      reloaded = DistributorOrders.get_order!(org.id, order.id)
      assert reloaded.status == :allocated

      items_by_product = Map.new(reloaded.items, &{&1.product_id, &1})
      item_a = Map.fetch!(items_by_product, product_a.id)
      item_b = Map.fetch!(items_by_product, product_b.id)

      assert item_a.quantity_allocated == 30
      assert item_b.quantity_allocated == 0

      updated_batch = Repo.get!(ThamaniDawa.Batches.Batch, batch_a.id)
      assert updated_batch.remaining_quantity == 70

      lines = Repo.all(from l in ShipmentLine, where: l.shipment_id == ^shipment.id)
      assert length(lines) == 1
      assert hd(lines).product_id == product_a.id
    end

    test "spreads allocation across multiple FEFO batches", %{
      org: org,
      warehouse: warehouse,
      customer: customer,
      product_a: product_a,
      batch_a: batch_a
    } do
      batch_b =
        batch_fixture(%{
          organization_id: org.id,
          product_id: product_a.id,
          site_id: warehouse.id,
          quantity: 50,
          expiry_date: ~D[2028-01-01]
        })

      order = order_fixture(org.id, customer.id, [{product_a.id, 120, 500}])

      assert {:ok, {shipment, _carton}} =
               DistributorShipments.allocate_order(org.id, order, warehouse.id)

      lines =
        Repo.all(
          from l in ShipmentLine,
            where: l.shipment_id == ^shipment.id,
            order_by: [asc: l.batch_id]
        )

      assert length(lines) == 2
      assert Enum.sum(Enum.map(lines, & &1.quantity)) == 120

      updated_a = Repo.get!(ThamaniDawa.Batches.Batch, batch_a.id)
      updated_b = Repo.get!(ThamaniDawa.Batches.Batch, batch_b.id)
      assert updated_a.remaining_quantity == 0
      assert updated_b.remaining_quantity == 30
    end

    test "returns :not_pending when order is already allocated", %{
      org: org,
      warehouse: warehouse,
      customer: customer,
      product_a: product_a
    } do
      order = order_fixture(org.id, customer.id, [{product_a.id, 10, 500}])
      {:ok, _} = DistributorShipments.allocate_order(org.id, order, warehouse.id)

      reloaded = DistributorOrders.get_order!(org.id, order.id)

      assert {:error, :not_pending} =
               DistributorShipments.allocate_order(org.id, reloaded, warehouse.id)
    end

    test "returns :missing_gs1_company_prefix when org has no GS1 prefix", _context do
      org_no_gs1 = ThamaniDawa.OrganizationsFixtures.organization_fixture()
      warehouse_no_gs1 = warehouse_fixture(org_no_gs1.id)
      product_no_gs1 = product_fixture(%{organization_id: org_no_gs1.id})
      customer_no_gs1 = customer_fixture(org_no_gs1.id)

      _batch =
        batch_fixture(%{
          organization_id: org_no_gs1.id,
          product_id: product_no_gs1.id,
          site_id: warehouse_no_gs1.id,
          quantity: 50
        })

      order = order_fixture(org_no_gs1.id, customer_no_gs1.id, [{product_no_gs1.id, 10, 100}])

      assert {:error, :missing_gs1_company_prefix} =
               DistributorShipments.allocate_order(org_no_gs1.id, order, warehouse_no_gs1.id)

      reloaded = DistributorOrders.get_order!(org_no_gs1.id, order.id)
      assert reloaded.status == :pending
    end

    test "creates exactly one carton with a valid 18-digit SSCC", %{
      org: org,
      warehouse: warehouse,
      customer: customer,
      product_a: product_a
    } do
      order = order_fixture(org.id, customer.id, [{product_a.id, 5, 500}])
      {:ok, {shipment, carton}} = DistributorShipments.allocate_order(org.id, order, warehouse.id)

      assert carton.sequence_in_shipment == 1
      assert carton.shipment_id == shipment.id
      assert String.length(carton.sscc) == 18
      assert String.match?(carton.sscc, ~r/^\d{18}$/)

      db_cartons = Repo.all(from c in Carton, where: c.shipment_id == ^shipment.id)
      assert length(db_cartons) == 1
    end

    test "confirms selected batches for each order line and issues an invoice once complete", %{
      org: org,
      warehouse: warehouse,
      customer: customer,
      product_a: product_a,
      product_b: product_b,
      batch_a: batch_a
    } do
      batch_b =
        batch_fixture(%{
          organization_id: org.id,
          product_id: product_b.id,
          site_id: warehouse.id,
          quantity: 30
        })

      order =
        order_fixture(
          org.id,
          customer.id,
          [
            {product_a.id, 25, 500},
            {product_b.id, 30, 200}
          ],
          delivery_address: nil
        )

      [item_a, item_b] = order.items

      assert {:ok, shipment} =
               DistributorShipments.allocate_order_item(
                 org.id,
                 order,
                 item_a,
                 warehouse.id,
                 [%{batch_id: batch_a.id, quantity: 25}]
               )

      after_first = DistributorOrders.get_order!(org.id, order.id)
      assert after_first.status == :pending
      assert after_first.invoice == nil

      assert {:ok, ^shipment} =
               DistributorShipments.allocate_order_item(
                 org.id,
                 after_first,
                 Enum.find(after_first.items, &(&1.id == item_b.id)),
                 warehouse.id,
                 [%{batch_id: batch_b.id, quantity: 30}]
               )

      completed = DistributorOrders.get_order!(org.id, order.id)
      assert completed.status == :allocated
      assert completed.invoice != nil
      assert completed.invoice.total == 18_500
    end
  end

  describe "dispatch_order/2" do
    test "dispatches an allocated order and issues an invoice", %{
      org: org,
      warehouse: warehouse,
      customer: customer,
      product_a: product_a
    } do
      order = order_fixture(org.id, customer.id, [{product_a.id, 20, 500}])
      {:ok, _} = DistributorShipments.allocate_order(org.id, order, warehouse.id)
      allocated = DistributorOrders.get_order!(org.id, order.id)

      assert {:ok, {shipment, invoice}} = DistributorShipments.dispatch_order(org.id, allocated)

      assert shipment.status == "dispatched"
      assert shipment.dispatched_at != nil

      reloaded = DistributorOrders.get_order!(org.id, order.id)
      assert reloaded.status == :dispatched

      assert invoice.order_id == order.id
      assert invoice.customer_id == customer.id
      assert invoice.subtotal == 20 * 500
      assert invoice.total == 20 * 500
    end

    test "invoice only covers allocated quantities on partial allocation", %{
      org: org,
      warehouse: warehouse,
      customer: customer,
      product_a: product_a,
      product_b: product_b
    } do
      order =
        order_fixture(org.id, customer.id, [
          {product_a.id, 30, 500},
          {product_b.id, 50, 200}
        ])

      {:ok, _} = DistributorShipments.allocate_order(org.id, order, warehouse.id)
      allocated = DistributorOrders.get_order!(org.id, order.id)

      {:ok, {_shipment, invoice}} = DistributorShipments.dispatch_order(org.id, allocated)

      assert invoice.subtotal == 30 * 500
      assert invoice.total == 30 * 500
    end

    test "returns :not_allocated for a pending order", %{
      org: org,
      customer: customer,
      product_a: product_a
    } do
      order = order_fixture(org.id, customer.id, [{product_a.id, 10, 500}])
      assert {:error, :not_allocated} = DistributorShipments.dispatch_order(org.id, order)
    end

    test "does not re-run FEFO or touch batch quantities on dispatch", %{
      org: org,
      warehouse: warehouse,
      customer: customer,
      product_a: product_a,
      batch_a: batch_a
    } do
      order = order_fixture(org.id, customer.id, [{product_a.id, 25, 500}])
      {:ok, _} = DistributorShipments.allocate_order(org.id, order, warehouse.id)

      after_allocation = Repo.get!(ThamaniDawa.Batches.Batch, batch_a.id)
      assert after_allocation.remaining_quantity == 75

      allocated = DistributorOrders.get_order!(org.id, order.id)
      {:ok, _} = DistributorShipments.dispatch_order(org.id, allocated)

      after_dispatch = Repo.get!(ThamaniDawa.Batches.Batch, batch_a.id)
      assert after_dispatch.remaining_quantity == 75
    end
  end
end
