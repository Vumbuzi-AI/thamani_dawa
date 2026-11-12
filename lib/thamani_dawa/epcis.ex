defmodule ThamaniDawa.Epcis do
  @moduledoc """
  PPB Track & Trace event recording (docs/PPB_TNT_INTEGRATION.md).

  Called from inside the business transactions that produce reportable
  supply-chain actions — goods receipt posting (Receiving) and shipment
  approval (Packing + Shipping). Each call builds EPCIS 2.0 JSON-LD payloads
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
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites.Site

  @distributor "distributor"
  @facility "facility"

  @doc """
  Records D1 Receiving events for a freshly posted goods receipt — one event
  per (site, supplier) group of posted lines. Lines received into org-level
  stock (no site) report against the organization's own GLN (`organizations.gln`)
  as `bizLocation`/`destinationList`, since there is no site to resolve one
  from yet. A supplier missing a GLN, or no inbound SSCC scanned (the Hub
  spec has no class-level fallback for Receiving), still produce `blocked`
  events.
  """
  def record_goods_receipt(%GoodsReceipt{} = receipt) do
    receipt = Repo.preload(receipt, items: [:site, :supplier])

    case org_prefix(receipt.organization_id) do
      {:ok, prefix} ->
        receipt.items
        |> Enum.group_by(fn item -> {item.site_id, item.supplier_id} end)
        |> Enum.sort_by(fn {key, _items} -> key end)
        |> Enum.map(fn {_key, items} -> enqueue_receiving(receipt, prefix, items) end)

      {:error, reason} ->
        [block_event(receipt.organization_id, "receiving", receipt, reason)]
    end
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
        args = %{
          event_id: Ecto.UUID.generate(),
          event_time: receipt.received_at,
          org_prefix: prefix,
          biz_location_gln: location_gln(first.site, receipt.organization_id),
          source_party_gln: first.supplier && first.supplier.gln,
          destination_party_gln: location_gln(first.site, receipt.organization_id),
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
          participant_tier: @distributor,
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
      ssccs: shipment.shippers |> Enum.map(& &1.sscc) |> Enum.reject(&is_nil/1)
    }

    case Event.shipping(args) do
      {:ok, payload} ->
        Outbox.enqueue(%{
          organization_id: shipment.organization_id,
          event_type: "shipping",
          participant_tier: @distributor,
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
    case Repo.get!(Organization, organization_id).gs1_company_prefix do
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
    do: "No supplier recorded for this receipt — attach a supplier to report this event."

  defp blocked_reason(:empty_event),
    do: "No inbound SSCC captured — Receiving requires at least one scanned case/pallet SSCC."

  defp blocked_reason({:destination_gln, :missing}),
    do: "Destination customer has no GLN on record."

  defp blocked_reason(reason), do: "Event could not be built: #{inspect(reason)}"

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
