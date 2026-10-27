defmodule ThamaniDawa.DistributorShipments do
  import Ecto.Query, warn: false

  alias ThamaniDawa.Batches
  alias ThamaniDawa.DistributorInvoices.{Invoice, InvoiceLine}
  alias ThamaniDawa.DistributorOrders.{Order, OrderItem}
  alias ThamaniDawa.DistributorShipments.{Carton, Shipment, ShipmentLine}
  alias ThamaniDawa.GS1.Sscc
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites

  def list_shipments(organization_id) do
    Repo.all(
      from shipment in Shipment,
        where: shipment.organization_id == ^organization_id,
        order_by: [desc: shipment.inserted_at],
        preload: [:customer, :warehouse]
    )
  end

  def get_shipment!(organization_id, id) do
    Repo.one!(
      from shipment in Shipment,
        where: shipment.organization_id == ^organization_id,
        where: shipment.id == ^id,
        preload: [
          :customer,
          :warehouse,
          order: [:customer],
          lines: [:product, :batch],
          cartons: [lines: [:product, :batch]]
        ]
    )
  end

  @doc """
  Gets a single shipment's cartons, each preloaded with its assigned lines.
  """
  def list_cartons(shipment_id) do
    Repo.all(
      from c in Carton,
        where: c.shipment_id == ^shipment_id,
        order_by: [asc: c.sequence_in_shipment],
        preload: [lines: [:product, :batch]]
    )
  end

  @doc """
  Creates the next carton for a dispatched shipment, auto-generating its SSCC
  from the organization's GS1 Company Prefix.

  Returns `{:error, :missing_gs1_company_prefix}` if the prefix hasn't been set.
  """
  def create_carton(organization_id, %Shipment{} = shipment) do
    true = shipment.organization_id == organization_id

    case Sscc.generate(organization_id) do
      {:ok, sscc} ->
        sequence =
          Repo.aggregate(
            from(c in Carton, where: c.shipment_id == ^shipment.id),
            :count,
            :id
          ) + 1

        %Carton{}
        |> Carton.changeset(%{
          sscc: sscc,
          sequence_in_shipment: sequence,
          shipment_id: shipment.id,
          organization_id: organization_id
        })
        |> Repo.insert()

      {:error, :missing_gs1_company_prefix} = error ->
        error
    end
  end

  @doc """
  Assigns a shipment line to a carton. The carton must belong to the same
  shipment as the line. Passing `nil` for `carton_id` removes the assignment.
  """
  def assign_line_to_carton(organization_id, line_id, carton_id) do
    line = Repo.get!(ShipmentLine, line_id)
    shipment = Repo.get!(Shipment, line.shipment_id)
    true = shipment.organization_id == organization_id

    if carton_id do
      carton = Repo.get!(Carton, carton_id)
      true = carton.shipment_id == line.shipment_id
    end

    line
    |> ShipmentLine.changeset(%{carton_id: carton_id})
    |> Repo.update()
  end

  @doc """
  Allocates stock for a pending order from a warehouse using FEFO, reserving
  stock per order line (partial-aware), and creates a Shipment with status
  "allocated" plus a single carton carrying a GS1 SSCC.

  Each order item's `quantity_allocated` is updated to reflect how much stock
  was actually reserved — which may be less than `quantity` when a product is
  partially or entirely out of stock. A zero-stock item does not fail the whole
  allocation.

  Returns `{:ok, {shipment, carton}}` on success, or:
  - `{:error, :not_pending}` if `order.status != :pending`
  - `{:error, :missing_gs1_company_prefix}` if GS1 prefix is not configured
  """
  def allocate_order(organization_id, %Order{} = order, warehouse_site_id) do
    Repo.transaction(fn ->
      if order.status != :pending do
        Repo.rollback(:not_pending)
      end

      _warehouse = Sites.get_site!(organization_id, warehouse_site_id)

      sscc =
        case Sscc.generate(organization_id) do
          {:ok, value} -> value
          {:error, :missing_gs1_company_prefix} -> Repo.rollback(:missing_gs1_company_prefix)
        end

      shipment =
        %Shipment{}
        |> Shipment.changeset(%{
          order_id: order.id,
          customer_id: order.customer_id,
          warehouse_id: warehouse_site_id,
          destination: order.delivery_address || "",
          status: "allocated"
        })
        |> Ecto.Changeset.put_change(:organization_id, organization_id)
        |> Repo.insert!()

      Enum.each(order.items, fn item ->
        reserve_item(organization_id, warehouse_site_id, shipment, item)
      end)

      carton =
        %Carton{}
        |> Carton.changeset(%{
          sscc: sscc,
          sequence_in_shipment: 1,
          shipment_id: shipment.id,
          organization_id: organization_id
        })
        |> Repo.insert!()

      _invoice = create_invoice!(organization_id, order, shipment, now())

      order
      |> Order.changeset(%{status: :allocated})
      |> Repo.update!()

      {shipment, carton}
    end)
  end

  @doc "Allocates an order from operator-selected, FEFO-eligible batch quantities."
  def allocate_order_with_picks(
        organization_id,
        %Order{} = order,
        warehouse_site_id,
        picks_by_item
      ) do
    Repo.transaction(fn ->
      if order.status != :pending, do: Repo.rollback(:not_pending)

      _warehouse = Sites.get_site!(organization_id, warehouse_site_id)

      sscc =
        case Sscc.generate(organization_id) do
          {:ok, value} -> value
          {:error, :missing_gs1_company_prefix} -> Repo.rollback(:missing_gs1_company_prefix)
        end

      shipment =
        %Shipment{}
        |> Shipment.changeset(%{
          order_id: order.id,
          customer_id: order.customer_id,
          warehouse_id: warehouse_site_id,
          destination: order.delivery_address || "",
          status: "allocated"
        })
        |> Ecto.Changeset.put_change(:organization_id, organization_id)
        |> Repo.insert!()

      Enum.each(order.items, fn item ->
        reserve_selected_item(
          organization_id,
          warehouse_site_id,
          shipment,
          item,
          Map.get(picks_by_item, item.id, [])
        )
      end)

      carton =
        %Carton{}
        |> Carton.changeset(%{
          sscc: sscc,
          sequence_in_shipment: 1,
          shipment_id: shipment.id,
          organization_id: organization_id
        })
        |> Repo.insert!()

      _invoice = create_invoice!(organization_id, order, shipment, now())

      order |> Order.changeset(%{status: :allocated}) |> Repo.update!()
      {shipment, carton}
    end)
  end

  def allocate_order_item(
        organization_id,
        %Order{} = order,
        %OrderItem{} = item,
        warehouse_id,
        picks
      ) do
    Repo.transaction(fn ->
      if order.status != :pending, do: Repo.rollback(:not_pending)
      shipment = shipment_for_allocation!(organization_id, order, warehouse_id)
      reserve_selected_item(organization_id, warehouse_id, shipment, item, picks)
      item |> OrderItem.changeset(%{allocation_processed: true}) |> Repo.update!()

      processed? =
        order.id
        |> processed_order_items?()

      if processed? do
        order |> Order.changeset(%{status: :allocated}) |> Repo.update!()
        _invoice = create_invoice!(organization_id, order, shipment, now())
      end

      shipment
    end)
  end

  @doc """
  Ships an already-allocated order, stamping `dispatched_at` on its shipment.

  Returns `{:ok, {shipment, invoice}}` on success, or:
  - `{:error, :not_allocated}` if `order.status != :allocated`
  """
  def dispatch_order(organization_id, %Order{} = order) do
    Repo.transaction(fn ->
      if order.status != :allocated do
        Repo.rollback(:not_allocated)
      end

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      shipment =
        Repo.one!(
          from s in Shipment,
            where: s.order_id == ^order.id,
            where: s.organization_id == ^organization_id
        )

      shipment =
        shipment
        |> Shipment.changeset(%{status: "dispatched", dispatched_at: now})
        |> Repo.update!()

      order
      |> Order.changeset(%{status: :dispatched})
      |> Repo.update!()

      invoice =
        Repo.get_by(Invoice, organization_id: organization_id, order_id: order.id) ||
          create_invoice!(organization_id, order, shipment, now)

      {shipment, invoice}
    end)
  end

  defp build_invoice_line_data(order, lines) do
    unit_price_by_product =
      Map.new(order.items, fn item -> {item.product_id, item.unit_price} end)

    lines
    |> Enum.group_by(& &1.product_id)
    |> Enum.map(fn {product_id, product_lines} ->
      total_qty = Enum.sum(Enum.map(product_lines, & &1.quantity))
      unit_price = Map.get(unit_price_by_product, product_id, hd(product_lines).unit_price)
      {product_id, total_qty, unit_price}
    end)
    |> Enum.filter(fn {_product_id, qty, _unit_price} -> qty > 0 end)
  end

  defp create_invoice!(organization_id, order, shipment, issued_at) do
    lines = Repo.all(from l in ShipmentLine, where: l.shipment_id == ^shipment.id)

    # Keep invoice number allocation compatible with the SQLite development
    # database as well as Postgres. The increment is still performed inside
    # the surrounding transaction before the number is read.
    {1, _} =
      Repo.update_all(
        from(o in Organization, where: o.id == ^organization_id),
        inc: [next_invoice_number: 1]
      )

    org = Repo.get!(Organization, organization_id)

    invoice_line_data = build_invoice_line_data(order, lines)

    subtotal =
      Enum.reduce(invoice_line_data, 0, fn {_product_id, qty, unit_price}, total ->
        total + qty * unit_price
      end)

    invoice =
      %Invoice{}
      |> Invoice.changeset(%{
        order_id: order.id,
        shipment_id: shipment.id,
        customer_id: order.customer_id,
        number: org.next_invoice_number,
        issued_at: issued_at,
        subtotal: subtotal,
        total: subtotal
      })
      |> Ecto.Changeset.put_change(:organization_id, organization_id)
      |> Repo.insert!()

    Enum.each(invoice_line_data, fn {product_id, qty, unit_price} ->
      %InvoiceLine{}
      |> InvoiceLine.changeset(%{
        invoice_id: invoice.id,
        product_id: product_id,
        quantity: qty,
        unit_price: unit_price,
        line_total: qty * unit_price
      })
      |> Repo.insert!()
    end)

    invoice
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp reserve_item(organization_id, warehouse_site_id, shipment, item) do
    batches = Batches.fefo_batches(organization_id, warehouse_site_id, item.product_id)

    {_remaining, total_allocated} =
      Enum.reduce_while(batches, {item.quantity, 0}, fn batch, {remaining, allocated} ->
        if remaining <= 0 do
          {:halt, {0, allocated}}
        else
          take = min(batch.remaining_quantity, remaining)

          %ShipmentLine{}
          |> ShipmentLine.changeset(%{
            shipment_id: shipment.id,
            product_id: item.product_id,
            batch_id: batch.id,
            quantity: take,
            unit_price: item.unit_price
          })
          |> Repo.insert!()

          decrement_batch(batch, take, remaining, allocated, item.product_id)
        end
      end)

    item
    |> OrderItem.changeset(%{quantity_allocated: total_allocated})
    |> Repo.update!()
  end

  defp decrement_batch(batch, take, remaining, allocated, product_id) do
    case Batches.decrement_remaining_quantity(batch, take) do
      {:ok, _} -> {:cont, {remaining - take, allocated + take}}
      {:error, _} -> Repo.rollback({:stock_update_failed, product_id})
    end
  end

  defp processed_order_items?(order_id) do
    Enum.all?(
      Repo.all(
        from i in OrderItem, where: i.order_id == ^order_id, select: i.allocation_processed
      )
    )
  end

  defp reserve_selected_item(organization_id, warehouse_site_id, shipment, item, picks) do
    if Enum.any?(picks, &(&1.quantity < 0)) or
         Enum.sum(Enum.map(picks, & &1.quantity)) > item.quantity do
      Repo.rollback(:invalid_allocation)
    end

    batches = Batches.fefo_batches(organization_id, warehouse_site_id, item.product_id)
    batches_by_id = Map.new(batches, &{&1.id, &1})

    total =
      Enum.reduce(picks, 0, fn %{batch_id: batch_id, quantity: quantity}, total ->
        if quantity == 0,
          do: total,
          else: reserve_selected_batch!(batches_by_id, shipment, item, batch_id, quantity) + total
      end)

    item |> OrderItem.changeset(%{quantity_allocated: total}) |> Repo.update!()
  end

  defp shipment_for_allocation!(organization_id, order, warehouse_id) do
    case Repo.get_by(Shipment, organization_id: organization_id, order_id: order.id) do
      %Shipment{} = shipment ->
        if shipment.warehouse_id != warehouse_id, do: Repo.rollback(:warehouse_mismatch)
        shipment

      nil ->
        sscc =
          case Sscc.generate(organization_id) do
            {:ok, value} -> value
            {:error, reason} -> Repo.rollback(reason)
          end

        shipment =
          %Shipment{}
          |> Shipment.changeset(%{
            order_id: order.id,
            customer_id: order.customer_id,
            warehouse_id: warehouse_id,
            destination: shipment_destination(order),
            status: "allocated"
          })
          |> Ecto.Changeset.put_change(:organization_id, organization_id)
          |> Repo.insert!()

        %Carton{}
        |> Carton.changeset(%{
          sscc: sscc,
          sequence_in_shipment: 1,
          shipment_id: shipment.id,
          organization_id: organization_id
        })
        |> Repo.insert!()

        shipment
    end
  end

  defp reserve_selected_batch!(batches_by_id, shipment, item, batch_id, quantity) do
    case Map.get(batches_by_id, batch_id) do
      nil ->
        Repo.rollback(:invalid_allocation)

      batch when batch.remaining_quantity < quantity ->
        Repo.rollback(:insufficient_stock)

      batch ->
        %ShipmentLine{}
        |> ShipmentLine.changeset(%{
          shipment_id: shipment.id,
          product_id: item.product_id,
          batch_id: batch.id,
          quantity: quantity,
          unit_price: item.unit_price
        })
        |> Repo.insert!()

        case Batches.decrement_remaining_quantity(batch, quantity) do
          {:ok, _} -> quantity
          {:error, _} -> Repo.rollback(:stock_update_failed)
        end
    end
  end

  defp shipment_destination(order) do
    delivery_address = (order.delivery_address || "") |> String.trim()

    cond do
      delivery_address != "" ->
        delivery_address

      Ecto.assoc_loaded?(order.customer) and is_binary(order.customer.address) and
          String.trim(order.customer.address) != "" ->
        String.trim(order.customer.address)

      true ->
        "Not specified"
    end
  end
end
