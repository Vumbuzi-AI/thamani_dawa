defmodule ThamaniDawa.Epcis do
  @moduledoc """
  PPB Track & Trace event recording (docs/PPB_TNT_INTEGRATION.md).

  Called from inside the business transactions that produce reportable
  supply-chain actions — goods receipt posting (Receiving), shipment
  approval (Packing + Shipping), and breaking a received case into
  mini-SSCCs (Unpacking + Packing). Each call builds EPCIS 2.0 JSON-LD payloads
  and enqueues them on the transactional outbox; events that cannot be built
  (missing partner GLN, missing GS1 prefix, malformed identifier) are
  enqueued as `blocked` with a human-readable reason instead of being
  silently dropped.
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.Distributor.Shipment
  alias ThamaniDawa.Distributor.Shipper
  alias ThamaniDawa.Epcis.Event
  alias ThamaniDawa.Epcis.Outbox
  alias ThamaniDawa.Epcis.OutboxEvent
  alias ThamaniDawa.GoodsReceipts.GoodsReceipt
  alias ThamaniDawa.Manufacturing.Batch, as: ManufacturerBatch
  alias ThamaniDawa.Manufacturing.Serial, as: ManufacturerSerial
  alias ThamaniDawa.Manufacturing.ShipperSscc
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Organizations.OrganizationGs1Prefix
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites.Site

  @distributor "distributor"
  @facility "facility"
  @manufacturer "manufacturer"

  @doc """
  Records a D1 Receiving event (distributor tier) for a completed customer
  return — stock physically coming back into the warehouse from a
  customer, the mirror image of a supplier goods receipt. One event per
  site among the return's items, sourced from the customer's GLN.
  """
  def record_customer_return(%ThamaniDawa.CustomerReturns.CustomerReturn{} = return) do
    return = Repo.preload(return, [:customer, :site, items: []])

    case org_prefix(return.organization_id) do
      {:ok, prefix} ->
        args = %{
          event_id: Ecto.UUID.generate(),
          event_time: now(),
          org_prefix: prefix,
          biz_location_gln: location_gln(return.site, return.organization_id),
          source_party_gln: return.customer.gln,
          destination_party_gln: location_gln(return.site, return.organization_id),
          disposition: "returned",
          grn_number: "CRET-#{return.id}",
          ssccs: []
        }

        case Event.receiving(args) do
          {:ok, payload} ->
            Outbox.enqueue(%{
              organization_id: return.organization_id,
              event_type: "receiving",
              participant_tier: @distributor,
              payload: payload,
              occurred_at: args.event_time,
              source_type: "customer_return",
              source_id: return.id
            })

          {:error, reason} ->
            block_event(return.organization_id, "receiving", return, reason)
        end

      {:error, reason} ->
        block_event(return.organization_id, "receiving", return, reason)
    end
  end

  @doc """
  Records D1 Receiving events for a freshly posted goods receipt. A
  distributor-portal receipt (`origin_gln` set — one live-resolved party for
  the whole receipt, see `ThamaniDawa.GoodsReceipts.receive_delivery/5`)
  produces one event per site among its posted lines, using the receipt's
  own `origin_gln`/`origin_company` as the source party. Every other
  receipt (pharmacy/lab org portal, still per-line `Suppliers.Supplier`)
  groups by `(site, supplier)` exactly as before. Lines received into
  org-level stock (no site) report against the organization's own GLN
  (`organizations.gln`) as `bizLocation`/`destinationList`, since there is
  no site to resolve one from yet. A supplier missing a GLN, or no inbound
  SSCC scanned (the Hub spec has no class-level fallback for Receiving),
  still produce `blocked` events.
  """
  def record_goods_receipt(%GoodsReceipt{} = receipt) do
    receipt = Repo.preload(receipt, items: [:site, :supplier])

    case org_prefix(receipt.organization_id) do
      {:ok, prefix} -> group_receipt_items(receipt, prefix)
      {:error, reason} -> [block_event(receipt.organization_id, "receiving", receipt, reason)]
    end
  end

  defp group_receipt_items(%GoodsReceipt{origin_gln: nil} = receipt, prefix) do
    receipt.items
    |> Enum.group_by(fn item -> {item.site_id, item.supplier_id} end)
    |> Enum.sort_by(fn {key, _items} -> key end)
    |> Enum.map(fn {_key, items} -> enqueue_receiving(receipt, prefix, items) end)
  end

  defp group_receipt_items(%GoodsReceipt{} = receipt, prefix) do
    receipt.items
    |> Enum.group_by(& &1.site_id)
    |> Enum.sort_by(fn {site_id, _items} -> site_id end)
    |> Enum.map(fn {_site_id, items} ->
      enqueue_receiving(receipt, prefix, items, receipt.origin_gln)
    end)
  end

  @doc """
  Records D2 Packing (one per shipper, in sequence order) and D3 Shipping
  events for an approved shipment. Shipping's `occurred_at` lands after
  every packing event so the Hub receives them chronologically.
  """
  def record_shipment_approval(%Shipment{} = shipment) do
    shipment = Repo.preload(shipment, [shippers: [:items]], force: true)

    case org_prefix(shipment.organization_id) do
      {:ok, prefix} ->
        packing = Enum.map(shipment.shippers, &enqueue_packing(shipment, prefix, &1))
        [enqueue_shipping(shipment, prefix) | packing]

      {:error, reason} ->
        [block_event(shipment.organization_id, "shipping", shipment, reason)]
    end
  end

  defp shipment_tier(%Shipment{participant_tier: "manufacturer"}), do: @manufacturer
  defp shipment_tier(%Shipment{}), do: @distributor

  @doc """
  Records a D4 unpack of `source_batch` (only when that batch itself has an
  SSCC — loose stock has nothing to disaggregate), one D2-shaped packing
  event per newly minted mini-SSCC in `children`, and a decommission of the
  parent SSCC — the inbound case is fully disaggregated and no longer exists.

  Called inside the split transaction. The unpack covers the whole parent
  (every unit is now in a child, remainder included); each pack covers that
  child's own contents.
  """
  def record_mini_sscc_split(%ThamaniDawa.Batches.Batch{} = source_batch, children)
      when is_list(children) do
    source_batch = Repo.preload(source_batch, :site)

    case org_prefix(source_batch.organization_id) do
      {:ok, prefix} ->
        maybe_enqueue_unpack(source_batch, children, prefix)
        Enum.each(children, &enqueue_mini_pack(source_batch, &1, prefix))
        maybe_enqueue_decommission(source_batch, prefix)

      {:error, reason} ->
        if source_batch.sscc not in [nil, ""] do
          block_event(source_batch.organization_id, "unpacking", source_batch, reason)
          block_event(source_batch.organization_id, "decommissioning", source_batch, reason)
        end

        Enum.each(children, fn child ->
          block_event(child.organization_id, "packing", child, reason)
        end)
    end

    :ok
  end

  @doc """
  Records a unit-level break: one **Unpack** of the parent unit's SSCC (its
  whole contents across every line), one **Packing** per minted child unit,
  and a **Decommission** of the parent SSCC. `results` is a list of
  `%{line: parent_line_batch, children: [child_batch]}`. Content is per-child
  GTIN/lot, so a mixed case unpacks several products in one event. Called
  inside the break transaction.
  """
  def record_logistic_unit_break(%ThamaniDawa.Batches.LogisticUnit{} = unit, results, emptied?)
      when is_list(results) and is_boolean(emptied?) do
    unit = Repo.preload(unit, :site)

    case org_prefix(unit.organization_id) do
      {:ok, prefix} ->
        enqueue_unit_unpack(unit, results, prefix)

        Enum.each(results, fn %{line: line, children: children} ->
          Enum.each(children, &enqueue_unit_pack(unit, line, &1, prefix))
        end)

        # The SSCC is only retired once the case is fully emptied; a partial
        # break leaves the parent active with its remaining lines.
        if emptied?, do: enqueue_unit_decommission(unit, prefix)

      {:error, reason} ->
        block_event(
          unit.organization_id,
          "unpacking",
          "logistic_unit",
          unit.id,
          reason,
          @distributor
        )

        if emptied? do
          block_event(
            unit.organization_id,
            "decommissioning",
            "logistic_unit",
            unit.id,
            reason,
            @distributor
          )
        end

        Enum.each(results, fn %{children: children} ->
          Enum.each(children, fn child ->
            block_event(child.organization_id, "packing", child, reason)
          end)
        end)
    end

    :ok
  end

  defp enqueue_unit_unpack(unit, results, prefix) do
    gln = location_gln(unit.site, unit.organization_id)
    content = unit_removed_content(results)
    args = mini_sscc_event_args(nil, prefix, gln, unit.sscc, content, now())

    case Event.unpack(args) do
      {:ok, payload} ->
        Outbox.enqueue(%{
          organization_id: unit.organization_id,
          event_type: "unpacking",
          participant_tier: @distributor,
          payload: payload,
          occurred_at: args.event_time,
          source_type: "logistic_unit",
          source_id: unit.id
        })

      {:error, reason} ->
        block_event(
          unit.organization_id,
          "unpacking",
          "logistic_unit",
          unit.id,
          reason,
          @distributor
        )
    end
  end

  defp enqueue_unit_pack(unit, line, child, prefix) do
    gln = location_gln(unit.site, unit.organization_id)
    occurred_at = DateTime.add(now(), 1, :second)
    content = unit_packed_content(line, child)
    args = mini_sscc_event_args(nil, prefix, gln, child.sscc, content, occurred_at)

    case Event.packing(args) do
      {:ok, payload} ->
        Outbox.enqueue(%{
          organization_id: child.organization_id,
          event_type: "packing",
          participant_tier: @distributor,
          payload: payload,
          occurred_at: occurred_at,
          source_type: "batch",
          source_id: child.id
        })

      {:error, reason} ->
        block_event(child.organization_id, "packing", child, reason)
    end
  end

  defp enqueue_unit_decommission(unit, prefix) do
    gln = location_gln(unit.site, unit.organization_id)
    occurred_at = DateTime.add(now(), 2, :second)

    args = %{
      event_id: Ecto.UUID.generate(),
      event_time: occurred_at,
      org_prefix: prefix,
      biz_location_gln: gln,
      sscc: unit.sscc
    }

    case Event.decommission(args) do
      {:ok, payload} ->
        Outbox.enqueue(%{
          organization_id: unit.organization_id,
          event_type: "decommissioning",
          participant_tier: @distributor,
          payload: payload,
          occurred_at: occurred_at,
          source_type: "logistic_unit",
          source_id: unit.id
        })

      {:error, reason} ->
        block_event(
          unit.organization_id,
          "decommissioning",
          "logistic_unit",
          unit.id,
          reason,
          @distributor
        )
    end
  end

  # Whole-unit unpack content, keyed by each child's own product/lot so a mixed
  # case lists several GTINs. Serialized children go in childEPCs; quantity-only
  # children aggregate into a per-(gtin, lot) quantityList.
  defp unit_removed_content(results) do
    pairs =
      Enum.flat_map(results, fn %{line: line, children: children} ->
        Enum.map(children, &{line, &1})
      end)

    serialized = Enum.filter(pairs, fn {_line, child} -> child.serials != [] end)
    quantity_only = Enum.reject(pairs, fn {_line, child} -> child.serials != [] end)

    %{
      children:
        Enum.flat_map(serialized, fn {line, child} ->
          Enum.map(child.serials, &%{gtin: line.gtin, serial: &1})
        end),
      quantities:
        quantity_only
        |> Enum.group_by(fn {line, _child} -> {line.gtin, line.batch_no} end)
        |> Enum.map(fn {{gtin, lot}, group} ->
          %{
            gtin: gtin,
            lot: lot,
            quantity: Enum.reduce(group, 0, fn {_line, child}, sum -> sum + child.quantity end),
            uom: "EA"
          }
        end)
    }
  end

  defp unit_packed_content(line, %ThamaniDawa.Batches.Batch{serials: []} = child) do
    %{
      children: [],
      quantities: [%{gtin: line.gtin, lot: line.batch_no, quantity: child.quantity, uom: "EA"}]
    }
  end

  defp unit_packed_content(line, child) do
    %{
      children: Enum.map(child.serials, &%{gtin: line.gtin, serial: &1}),
      quantities: []
    }
  end

  defp maybe_enqueue_unpack(%ThamaniDawa.Batches.Batch{sscc: sscc}, _children, _prefix)
       when sscc in [nil, ""],
       do: :ok

  defp maybe_enqueue_unpack(source_batch, children, prefix) do
    gln = location_gln(source_batch.site, source_batch.organization_id)
    content = removed_content(source_batch, children)
    args = mini_sscc_event_args(source_batch, prefix, gln, source_batch.sscc, content, now())

    case Event.unpack(args) do
      {:ok, payload} ->
        Outbox.enqueue(%{
          organization_id: source_batch.organization_id,
          event_type: "unpacking",
          participant_tier: @distributor,
          payload: payload,
          occurred_at: args.event_time,
          source_type: "batch",
          source_id: source_batch.id
        })

      {:error, reason} ->
        block_event(source_batch.organization_id, "unpacking", source_batch, reason)
    end
  end

  defp enqueue_mini_pack(source_batch, child, prefix) do
    gln = location_gln(source_batch.site, source_batch.organization_id)
    # One second after the unpack so a hub that sorts by eventTime sees the
    # case broken before the mini-SSCCs are packed.
    occurred_at = DateTime.add(now(), 1, :second)
    content = packed_content(source_batch, child)
    args = mini_sscc_event_args(source_batch, prefix, gln, child.sscc, content, occurred_at)

    case Event.packing(args) do
      {:ok, payload} ->
        Outbox.enqueue(%{
          organization_id: child.organization_id,
          event_type: "packing",
          participant_tier: @distributor,
          payload: payload,
          occurred_at: occurred_at,
          source_type: "batch",
          source_id: child.id
        })

      {:error, reason} ->
        block_event(child.organization_id, "packing", child, reason)
    end
  end

  defp maybe_enqueue_decommission(%ThamaniDawa.Batches.Batch{sscc: sscc}, _prefix)
       when sscc in [nil, ""],
       do: :ok

  defp maybe_enqueue_decommission(source_batch, prefix) do
    gln = location_gln(source_batch.site, source_batch.organization_id)
    # Two seconds after the unpack so a hub that sorts by eventTime sees the
    # case unpacked and the mini-SSCCs packed before the parent is retired.
    occurred_at = DateTime.add(now(), 2, :second)

    args = %{
      event_id: Ecto.UUID.generate(),
      event_time: occurred_at,
      org_prefix: prefix,
      biz_location_gln: gln,
      sscc: source_batch.sscc
    }

    case Event.decommission(args) do
      {:ok, payload} ->
        Outbox.enqueue(%{
          organization_id: source_batch.organization_id,
          event_type: "decommissioning",
          participant_tier: @distributor,
          payload: payload,
          occurred_at: occurred_at,
          source_type: "batch",
          source_id: source_batch.id
        })

      {:error, reason} ->
        block_event(source_batch.organization_id, "decommissioning", source_batch, reason)
    end
  end

  defp removed_content(source_batch, children) do
    if source_batch.serials == [] do
      %{
        children: [],
        quantities: [
          %{
            gtin: source_batch.gtin,
            lot: source_batch.batch_no,
            quantity: Enum.reduce(children, 0, &(&1.quantity + &2)),
            uom: "EA"
          }
        ]
      }
    else
      %{
        children:
          children
          |> Enum.flat_map(& &1.serials)
          |> Enum.map(&%{gtin: source_batch.gtin, serial: &1}),
        quantities: []
      }
    end
  end

  # Quantity-only packs keep the parent's manufacturer lot. The child's
  # batch number is only a storage suffix (`LOT123-S1`), not a new lot.
  defp packed_content(source_batch, %ThamaniDawa.Batches.Batch{serials: []} = child) do
    %{
      children: [],
      quantities: [
        %{
          gtin: child.gtin,
          lot: source_batch.batch_no,
          quantity: child.quantity,
          uom: "EA"
        }
      ]
    }
  end

  defp packed_content(_source_batch, child) do
    %{
      children: Enum.map(child.serials, &%{gtin: child.gtin, serial: &1}),
      quantities: []
    }
  end

  defp mini_sscc_event_args(_source_batch, prefix, gln, parent_sscc, content, occurred_at) do
    %{
      event_id: Ecto.UUID.generate(),
      event_time: occurred_at,
      org_prefix: prefix,
      biz_location_gln: gln,
      parent_sscc: parent_sscc,
      children: content.children,
      quantities: content.quantities
    }
  end

  @doc """
  Records F2 Dispensing events (facility tier) for stock handed over a
  pharmacy counter — one event per dispense covering every FEFO-allocated
  batch line. An allocation becomes an `epcList` SGTIN only when it took
  exactly one unit under a known serial (a serial can never validly
  represent more than one physical item); every other allocation —
  multi-unit or unserialized — stays in the class-level `quantityList`.
  Called inside the dispense transaction.
  """
  def record_dispense(
        organization_id,
        site_id,
        item_id,
        allocations,
        source_type \\ "prescription_item"
      )
      when is_integer(organization_id) and is_integer(item_id) and is_list(allocations) do
    case site_id && Repo.get(Site, site_id) do
      %Site{} = site ->
        record_facility_event(
          organization_id,
          site,
          "dispensing",
          &dispense_event(organization_id, item_id, allocations, source_type, &1, &2)
        )

      _site ->
        :ok
    end
  end

  defp dispense_event(organization_id, item_id, allocations, source_type, site_gln, prefix) do
    {serialized, class_level} =
      Enum.split_with(allocations, fn allocation ->
        allocation.quantity == 1 and allocation.batch.serial not in [nil, ""]
      end)

    args = %{
      event_id: Ecto.UUID.generate(),
      event_time: now(),
      org_prefix: prefix,
      biz_location_gln: site_gln,
      epcs:
        Enum.map(serialized, fn allocation ->
          %{gtin: allocation.batch.gtin, serial: allocation.batch.serial}
        end),
      quantities:
        Enum.map(class_level, fn allocation ->
          %{
            gtin: allocation.batch.gtin,
            lot: allocation.batch.batch_no,
            quantity: allocation.quantity,
            uom: "EA"
          }
        end)
    }

    case Event.dispensing(args) do
      {:ok, payload} ->
        Outbox.enqueue(%{
          organization_id: organization_id,
          event_type: "dispensing",
          participant_tier: @facility,
          payload: payload,
          occurred_at: args.event_time,
          source_type: source_type,
          source_id: item_id
        })

      {:error, reason} ->
        block_event(
          organization_id,
          "dispensing",
          source_type,
          item_id,
          reason,
          @facility
        )
    end
  end

  @doc """
  Records F1 Receiving events (facility tier) when a pharmacy site confirms
  receipt of stock. Distributor goods receipts are excluded — their D1
  distributor-tier event already covers them — and only pharmacy-capable
  sites count as Healthcare Facility participants.
  """
  def record_facility_receipt(%ThamaniDawa.Batches.Batch{} = batch) do
    site = batch.site_id && Repo.get(Site, batch.site_id)

    if is_nil(batch.goods_receipt_id) and site && Site.pharmacy?(site) do
      received = Repo.preload(batch, :supplier)

      record_facility_event(
        received.organization_id,
        site,
        "receiving",
        &receipt_event(received, &1, &2)
      )
    else
      :ok
    end
  end

  defp receipt_event(%ThamaniDawa.Batches.Batch{} = batch, site_gln, prefix) do
    args = %{
      event_id: Ecto.UUID.generate(),
      event_time: now(),
      org_prefix: prefix,
      biz_location_gln: site_gln,
      source_party_gln: batch.supplier && batch.supplier.gln,
      destination_party_gln: site_gln,
      grn_number: "RECV-" <> Integer.to_string(batch.id),
      ssccs: if(batch.sscc, do: [batch.sscc], else: [])
    }

    case Event.receiving(args) do
      {:ok, payload} ->
        Outbox.enqueue(%{
          organization_id: batch.organization_id,
          event_type: "receiving",
          participant_tier: @facility,
          payload: payload,
          occurred_at: args.event_time,
          source_type: "batch",
          source_id: batch.id
        })

      {:error, reason} ->
        block_event(batch.organization_id, "receiving", "batch", batch.id, reason, @facility)
    end
  end

  @doc """
  Records a batch status-transition event (§4.3/§4.4) — damaged, expired,
  stolen, lost, exported, recalled, or destroyed. `reference`/
  `reference_type` are the incident/recall/destruction-certificate
  reference (`nil` for expiry, which needs none). The biz location is the
  batch's site GLN, or the organization's own GLN for org-level stock with
  no site yet.
  """
  def record_batch_status(
        %ThamaniDawa.Batches.Batch{} = batch,
        event_type,
        biz_step,
        disposition,
        reference,
        reference_type
      ) do
    site = batch.site_id && Repo.get(Site, batch.site_id)
    biz_location_gln = location_gln(site, batch.organization_id)

    case org_prefix(batch.organization_id) do
      {:ok, prefix} ->
        build_and_enqueue_status(
          batch,
          prefix,
          biz_location_gln,
          event_type,
          biz_step,
          disposition,
          reference,
          reference_type
        )

      {:error, reason} ->
        block_event(batch.organization_id, event_type, batch, reason)
    end
  end

  defp build_and_enqueue_status(
         batch,
         _prefix,
         biz_location_gln,
         event_type,
         _biz_step,
         _disposition,
         _reference,
         _reference_type
       )
       when biz_location_gln in [nil, ""] do
    block_event(batch.organization_id, event_type, batch, {:biz_location_gln, :missing})
  end

  defp build_and_enqueue_status(
         batch,
         prefix,
         biz_location_gln,
         event_type,
         biz_step,
         disposition,
         reference,
         reference_type
       ) do
    args = %{
      event_id: Ecto.UUID.generate(),
      event_time: now(),
      org_prefix: prefix,
      biz_location_gln: biz_location_gln,
      biz_step: biz_step,
      disposition: disposition,
      reference: reference,
      reference_type: reference_type,
      quantities: [
        %{gtin: batch.gtin, lot: batch.batch_no, quantity: batch.remaining_quantity, uom: "EA"}
      ]
    }

    case Event.status_change(args) do
      {:ok, payload} ->
        Outbox.enqueue(%{
          organization_id: batch.organization_id,
          event_type: event_type,
          participant_tier: @distributor,
          payload: payload,
          occurred_at: args.event_time,
          source_type: "batch",
          source_id: batch.id
        })

      {:error, reason} ->
        block_event(batch.organization_id, event_type, batch, reason)
    end
  end

  @doc """
  Records a manufacturer Commission ObjectEvent (ADD/`commissioning`/
  `active`) for a batch of freshly serialised units — the first EPCIS event
  a serial number ever gets, marking its entry into circulation.
  """
  def record_manufacturer_commission(
        organization_id,
        product,
        %ManufacturerBatch{} = batch,
        serials,
        biz_location_gln \\ nil
      ) do
    case org_prefix(organization_id) do
      {:ok, prefix} ->
        args = %{
          event_id: Ecto.UUID.generate(),
          event_time: now(),
          org_prefix: prefix,
          biz_location_gln: biz_location_gln || org_gln(organization_id),
          lot_number: batch.batch_no,
          item_expiration_date: batch.expiry_date,
          epcs: Enum.map(serials, &%{gtin: product.gtin, serial: &1.serial})
        }

        case Event.commission(args) do
          {:ok, payload} ->
            Outbox.enqueue(%{
              organization_id: organization_id,
              event_type: "commissioning",
              participant_tier: @manufacturer,
              payload: payload,
              occurred_at: args.event_time,
              source_type: "manufacturer_batch",
              source_id: batch.id
            })

          {:error, reason} ->
            block_event(
              organization_id,
              "commissioning",
              "manufacturer_batch",
              batch.id,
              reason,
              @manufacturer
            )
        end

      {:error, reason} ->
        block_event(
          organization_id,
          "commissioning",
          "manufacturer_batch",
          batch.id,
          reason,
          @manufacturer
        )
    end
  end

  @doc "Records the verified SSCC-to-SSCC manufacturer packing event for a pallet."
  def record_manufacturer_pallet_pack(organization_id, pallet, shippers, biz_location_gln \\ nil)
      when is_list(shippers) do
    case org_prefix(organization_id) do
      {:ok, prefix} ->
        args = %{
          event_id: Ecto.UUID.generate(),
          event_time: now(),
          org_prefix: prefix,
          biz_location_gln: biz_location_gln || org_gln(organization_id),
          parent_sscc: pallet.code,
          sscc_children: Enum.map(shippers, & &1.code)
        }

        case Event.sscc_packing(args) do
          {:ok, payload} ->
            Outbox.enqueue(%{
              organization_id: organization_id,
              event_type: "pallet_packing",
              participant_tier: @manufacturer,
              payload: payload,
              occurred_at: args.event_time,
              source_type: "manufacturer_pallet",
              source_id: pallet.id
            })

          {:error, reason} ->
            block_event(
              organization_id,
              "pallet_packing",
              "manufacturer_pallet",
              pallet.id,
              reason,
              @manufacturer
            )
        end

      {:error, reason} ->
        block_event(
          organization_id,
          "pallet_packing",
          "manufacturer_pallet",
          pallet.id,
          reason,
          @manufacturer
        )
    end
  end

  @doc """
  Records a manufacturer Pack AggregationEvent for a shipper SSCC minted
  around `batches`. Packed at lot level (`quantityList`) — the member API
  mints the SSCC and its serials independently, so this platform does not
  yet know which specific serials landed in which shipper.
  """
  def record_manufacturer_pack(organization_id, product, %ShipperSscc{} = shipper_sscc, batches)
      when is_list(batches) do
    case org_prefix(organization_id) do
      {:ok, prefix} ->
        args = %{
          event_id: Ecto.UUID.generate(),
          event_time: now(),
          org_prefix: prefix,
          biz_location_gln: org_gln(organization_id),
          parent_sscc: shipper_sscc.code,
          children: [],
          quantities:
            Enum.map(batches, fn batch ->
              %{gtin: product.gtin, lot: batch.batch_no, quantity: serial_count(batch), uom: "EA"}
            end)
        }

        case Event.packing(args) do
          {:ok, payload} ->
            Outbox.enqueue(%{
              organization_id: organization_id,
              event_type: "packing",
              participant_tier: @manufacturer,
              payload: payload,
              occurred_at: args.event_time,
              source_type: "manufacturer_shipper_sscc",
              source_id: shipper_sscc.id
            })

          {:error, reason} ->
            block_event(
              organization_id,
              "packing",
              "manufacturer_shipper_sscc",
              shipper_sscc.id,
              reason,
              @manufacturer
            )
        end

      {:error, reason} ->
        block_event(
          organization_id,
          "packing",
          "manufacturer_shipper_sscc",
          shipper_sscc.id,
          reason,
          @manufacturer
        )
    end
  end

  @doc """
  Records a manufacturer Pack AggregationEvent for a shipper SSCC minted
  around a specific split of primary serials (the make-to-order path,
  where several shippers share one source batch) — `childEPCs` carry only
  the serials assigned to this shipper, not the whole batch's quantity.
  """
  def record_manufacturer_serial_pack(
        organization_id,
        product,
        %ShipperSscc{} = shipper_sscc,
        serials,
        biz_location_gln
      )
      when is_list(serials) do
    case org_prefix(organization_id) do
      {:ok, prefix} ->
        args = %{
          event_id: Ecto.UUID.generate(),
          event_time: now(),
          org_prefix: prefix,
          biz_location_gln: biz_location_gln || org_gln(organization_id),
          parent_sscc: shipper_sscc.code,
          children: Enum.map(serials, &%{gtin: product.gtin, serial: &1.serial}),
          quantities: []
        }

        case Event.packing(args) do
          {:ok, payload} ->
            Outbox.enqueue(%{
              organization_id: organization_id,
              event_type: "packing",
              participant_tier: @manufacturer,
              payload: payload,
              occurred_at: args.event_time,
              source_type: "manufacturer_shipper_sscc",
              source_id: shipper_sscc.id
            })

          {:error, reason} ->
            block_event(
              organization_id,
              "packing",
              "manufacturer_shipper_sscc",
              shipper_sscc.id,
              reason,
              @manufacturer
            )
        end

      {:error, reason} ->
        block_event(
          organization_id,
          "packing",
          "manufacturer_shipper_sscc",
          shipper_sscc.id,
          reason,
          @manufacturer
        )
    end
  end

  @doc """
  Records a manufacturer Ship ObjectEvent for the outermost SSCCs dispatched
  to `destination_gln`. When shippers are on a pallet, pass the pallet SSCC —
  the shipper-to-pallet containment was already reported by the aggregation
  event, so listing both would double-count the same physical goods.
  """
  def record_manufacturer_ship(
        organization_id,
        shipment_id,
        sscc_codes,
        origin_gln,
        destination_gln,
        order_number,
        occurred_at \\ now()
      )
      when is_list(sscc_codes) do
    case org_prefix(organization_id) do
      {:ok, prefix} ->
        args = %{
          event_id: Ecto.UUID.generate(),
          event_time: occurred_at,
          org_prefix: prefix,
          biz_location_gln: origin_gln,
          destination_gln: destination_gln,
          order_number: order_number,
          disposition: "in_transit",
          ssccs: sscc_codes
        }

        case Event.shipping(args) do
          {:ok, payload} ->
            Outbox.enqueue(%{
              organization_id: organization_id,
              event_type: "shipping",
              participant_tier: @manufacturer,
              payload: payload,
              occurred_at: args.event_time,
              source_type: "manufacturer_shipment",
              source_id: shipment_id
            })

          {:error, reason} ->
            block_event(
              organization_id,
              "shipping",
              "manufacturer_shipment",
              shipment_id,
              reason,
              @manufacturer
            )
        end

      {:error, reason} ->
        block_event(
          organization_id,
          "shipping",
          "manufacturer_shipment",
          shipment_id,
          reason,
          @manufacturer
        )
    end
  end

  defp serial_count(%ManufacturerBatch{id: id}) do
    Repo.aggregate(from(s in ManufacturerSerial, where: s.manufacturer_batch_id == ^id), :count)
  end

  @doc """
  Voids or corrects an already-stored EPCIS event (docs/PPB_TNT_INTEGRATION.md
  §7): clones the stored payload, injects an `errorDeclaration`, and enqueues
  a fresh outbox row reusing the original `event_id` — the only legal
  same-eventID resubmission. The original row keeps its audit trail.

  Only events the Hub has actually stored (`"accepted"`/`"warning"`) can be
  declared; anything still pending or rejected is handled by `Outbox.resubmit`
  or a payload fix instead. `opts`:

    * `:declaration_time` — defaults to now, bumped to one second past the
      original `eventTime` when now is not strictly later
    * `:corrective_event_ids` — optional list of `urn:uuid:` references
  """
  def declare_error(%OutboxEvent{} = event, reason, opts \\ []) do
    with :ok <- stored?(event),
         declaration_time = declaration_time(event, opts),
         {:ok, amended} <-
           Event.error_declaration(event.payload, %{
             declaration_time: declaration_time,
             reason: reason,
             corrective_event_ids: Keyword.get(opts, :corrective_event_ids, [])
           }) do
      {:ok,
       Outbox.enqueue(%{
         organization_id: event.organization_id,
         event_id: event.event_id,
         event_type: event.event_type,
         participant_tier: event.participant_tier,
         payload: amended,
         occurred_at: declaration_time,
         source_type: event.source_type,
         source_id: event.source_id
       })}
    end
  end

  defp stored?(%OutboxEvent{status: status}) when status in ["accepted", "warning"], do: :ok
  defp stored?(%OutboxEvent{status: _status}), do: {:error, :not_stored}

  defp declaration_time(event, opts) do
    requested = Keyword.get(opts, :declaration_time, now())

    case stored_event_time(event) do
      {:ok, %DateTime{} = event_time} ->
        if DateTime.compare(requested, event_time) == :gt do
          requested
        else
          event_time |> DateTime.add(1, :second) |> DateTime.truncate(:second)
        end

      _ ->
        DateTime.truncate(requested, :second)
    end
  end

  defp stored_event_time(%OutboxEvent{payload: %{"eventTime" => iso}}) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, event_time, _offset} -> {:ok, event_time}
      {:error, _reason} -> {:error, :invalid}
    end
  end

  defp stored_event_time(_event), do: {:error, :missing}

  # Pharmacy-site facility events: the site's GLN is the bizLocation/readPoint,
  # so both a pharmacy site and the org's GS1 company prefix are prerequisites.
  defp record_facility_event(organization_id, %Site{} = site, event_type, build) do
    if site.gln in [nil, ""] do
      block_event(
        organization_id,
        event_type,
        "site",
        site.id,
        {:biz_location_gln, :missing},
        @facility
      )

      :ok
    else
      case org_prefix(organization_id) do
        {:ok, prefix} ->
          build.(site.gln, prefix)

        {:error, reason} ->
          block_event(organization_id, event_type, "site", site.id, reason, @facility)

          :ok
      end
    end
  end

  defp enqueue_receiving(receipt, prefix, [first | _rest] = items) do
    case supplier_check(first) do
      :ok ->
        build_and_enqueue_receiving(
          receipt,
          prefix,
          first.site,
          items,
          first.supplier && first.supplier.gln
        )

      {:error, reason} ->
        block_event(receipt.organization_id, "receiving", receipt, reason)
    end
  end

  # Distributor-portal path: the source party's GLN was already resolved
  # and verified at receive time (`Distributor.GlnLookup.resolve_party/1`),
  # so there's no per-line supplier to check here.
  defp enqueue_receiving(receipt, prefix, [first | _rest] = items, origin_gln) do
    build_and_enqueue_receiving(receipt, prefix, first.site, items, origin_gln)
  end

  defp build_and_enqueue_receiving(receipt, prefix, site, items, source_party_gln) do
    args = %{
      event_id: Ecto.UUID.generate(),
      event_time: receipt.received_at,
      org_prefix: prefix,
      biz_location_gln: location_gln(site, receipt.organization_id),
      source_party_gln: source_party_gln,
      destination_party_gln: location_gln(site, receipt.organization_id),
      disposition: if(receipt.is_return, do: "returned", else: "active"),
      grn_number: receipt.number,
      ssccs:
        items
        |> Enum.map(& &1.sscc)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
    }

    case Event.receiving(args) do
      {:ok, payload} ->
        Outbox.enqueue(%{
          organization_id: receipt.organization_id,
          event_type: "receiving",
          participant_tier: @distributor,
          payload: payload,
          occurred_at: receipt.received_at,
          source_type: "goods_receipt",
          source_id: receipt.id
        })

      {:error, reason} ->
        block_event(receipt.organization_id, "receiving", receipt, reason)
    end
  end

  defp supplier_check(%{supplier_id: nil}), do: {:error, :no_supplier}
  defp supplier_check(_item), do: :ok

  defp enqueue_packing(shipment, prefix, %Shipper{} = shipper) do
    occurred_at = shipper.sscc_assigned_at || now()

    args = %{
      event_id: Ecto.UUID.generate(),
      event_time: occurred_at,
      org_prefix: prefix,
      biz_location_gln: shipment.origin_gln,
      parent_sscc: shipper.sscc,
      children: Enum.map(shipper.items, fn item -> %{gtin: item.gtin, serial: item.serial} end)
    }

    case Event.packing(args) do
      {:ok, payload} ->
        Outbox.enqueue(%{
          organization_id: shipment.organization_id,
          event_type: "packing",
          participant_tier: shipment_tier(shipment),
          payload: payload,
          occurred_at: occurred_at,
          source_type: "shipper",
          source_id: shipper.id
        })

      {:error, reason} ->
        block_event(shipment.organization_id, "packing", shipment, reason)
    end
  end

  defp enqueue_shipping(shipment, prefix) do
    occurred_at =
      shipment.shippers
      |> Enum.map(& &1.sscc_assigned_at)
      |> Enum.reject(&is_nil/1)
      |> Enum.max(DateTime, fn -> now() end)
      |> DateTime.add(1)

    args = %{
      event_id: Ecto.UUID.generate(),
      event_time: occurred_at,
      org_prefix: prefix,
      biz_location_gln: shipment.origin_gln,
      destination_gln: shipment.destination_gln,
      order_number: shipment.order_number,
      disposition: if(shipment.is_return, do: "returned", else: "in_transit"),
      ssccs: shipment.shippers |> Enum.map(& &1.sscc) |> Enum.reject(&is_nil/1)
    }

    case Event.shipping(args) do
      {:ok, payload} ->
        Outbox.enqueue(%{
          organization_id: shipment.organization_id,
          event_type: "shipping",
          participant_tier: shipment_tier(shipment),
          payload: payload,
          occurred_at: occurred_at,
          source_type: "shipment",
          source_id: shipment.id
        })

      {:error, reason} ->
        block_event(shipment.organization_id, "shipping", shipment, reason)
    end
  end

  defp block_event(organization_id, event_type, source, reason, tier \\ @distributor) do
    {source_type, source_id} = source_ref(source)

    Outbox.block(
      %{
        organization_id: organization_id,
        event_type: event_type,
        participant_tier: tier,
        payload: %{},
        occurred_at: now(),
        source_type: source_type,
        source_id: source_id
      },
      blocked_reason(reason)
    )
  end

  defp block_event(organization_id, event_type, source_type, source_id, reason, tier) do
    Outbox.block(
      %{
        organization_id: organization_id,
        event_type: event_type,
        participant_tier: tier,
        payload: %{},
        occurred_at: now(),
        source_type: source_type,
        source_id: source_id
      },
      blocked_reason(reason)
    )
  end

  defp source_ref(%GoodsReceipt{id: id}), do: {"goods_receipt", id}
  defp source_ref(%Shipment{id: id}), do: {"shipment", id}
  defp source_ref(%ThamaniDawa.Batches.Batch{id: id}), do: {"batch", id}
  defp source_ref(_other), do: {nil, nil}

  defp org_prefix(organization_id) do
    query =
      from p in OrganizationGs1Prefix,
        where: p.organization_id == ^organization_id and p.is_primary,
        select: p.prefix

    case Repo.one(query) do
      prefix when prefix in [nil, ""] -> {:error, :missing_gs1_company_prefix}
      prefix -> {:ok, prefix}
    end
  end

  defp org_gln(organization_id), do: Repo.get!(Organization, organization_id).gln

  defp location_gln(nil, organization_id), do: org_gln(organization_id)
  defp location_gln(site, _organization_id), do: site.gln

  defp blocked_reason(:missing_gs1_company_prefix),
    do: "Organization has no GS1 company prefix configured."

  defp blocked_reason({:biz_location_gln, :missing}),
    do: "Location has no GLN on record (events need a site or organization GLN)."

  defp blocked_reason({:source_party_gln, :missing}),
    do: "Supplier has no GLN on record."

  defp blocked_reason(:no_supplier),
    do: "No supplier recorded for this receipt. Attach a supplier to report this event."

  defp blocked_reason(:empty_event),
    do: "No inbound SSCC captured. Receiving requires at least one scanned case/pallet SSCC."

  defp blocked_reason({:destination_gln, :missing}),
    do: "Destination customer has no GLN on record."

  defp blocked_reason(reason), do: "Event could not be built: #{inspect(reason)}"

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
