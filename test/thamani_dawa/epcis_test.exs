defmodule ThamaniDawa.EpcisTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.AccountsFixtures
  alias ThamaniDawa.Batches
  alias ThamaniDawa.Distributor
  alias ThamaniDawa.DistributorFixtures
  alias ThamaniDawa.Epcis
  alias ThamaniDawa.Epcis.Outbox
  alias ThamaniDawa.Epcis.OutboxEvent
  alias ThamaniDawa.GoodsReceipts
  alias ThamaniDawa.OrganizationsFixtures
  alias ThamaniDawa.PatientVisitsFixtures
  alias ThamaniDawa.Prescriptions
  alias ThamaniDawa.PrescriptionsFixtures
  alias ThamaniDawa.ProductsFixtures
  alias ThamaniDawa.SitesFixtures
  alias ThamaniDawa.SuppliersFixtures

  describe "record_goods_receipt/1 via GoodsReceipts.receive_delivery/4" do
    setup do
      organization = DistributorFixtures.distributor_organization_fixture()
      user = AccountsFixtures.user_fixture(%{organization_id: organization.id})

      warehouse =
        SitesFixtures.site_fixture(%{
          organization_id: organization.id,
          activities: [:distribution]
        })

      supplier = SuppliersFixtures.supplier_fixture(%{organization_id: organization.id})
      product = ProductsFixtures.product_fixture(%{organization_id: organization.id})

      %{
        organization: organization,
        user: user,
        warehouse: warehouse,
        supplier: supplier,
        product: product
      }
    end

    test "posting a receipt with a scanned SSCC enqueues a pending receiving event", ctx do
      assert {:ok, receipt} =
               GoodsReceipts.receive_delivery(
                 ctx.organization.id,
                 ctx.user.id,
                 [delivery_item(ctx, "LOT-EPCIS-1", 20, sscc: "006141411234567890")],
                 Ecto.UUID.generate()
               )

      assert [%OutboxEvent{} = event] = Outbox.pending_for_organization(ctx.organization.id)
      assert event.event_type == "receiving"
      assert event.participant_tier == "distributor"
      assert event.source_type == "goods_receipt"
      assert event.source_id == receipt.id
      assert event.status == "pending"

      assert event.payload["bizStep"] == "receiving"
      assert event.payload["disposition"] == "active"
      assert event.payload["epcList"] == ["urn:epc:id:sscc:0614141.0123456789"]

      assert [%{"bizTransaction" => transaction}] = event.payload["bizTransactionList"]
      assert transaction =~ receipt.number
    end

    test "a receipt with no scanned SSCC is blocked, not reported class-level", ctx do
      assert {:ok, _receipt} =
               GoodsReceipts.receive_delivery(
                 ctx.organization.id,
                 ctx.user.id,
                 [delivery_item(ctx, "LOT-EPCIS-NOSSCC", 20)],
                 Ecto.UUID.generate()
               )

      assert Outbox.pending_for_organization(ctx.organization.id) == []

      assert [%OutboxEvent{status: "blocked"} = event] = Outbox.list_events(ctx.organization.id)
      assert event.blocked_reason =~ "inbound SSCC"
    end

    test "a scanned inbound SSCC lands in the receiving event's epcList", ctx do
      assert {:ok, _receipt} =
               GoodsReceipts.receive_delivery(
                 ctx.organization.id,
                 ctx.user.id,
                 [delivery_item(ctx, "LOT-EPCIS-3", 10, sscc: "006141411234567890")],
                 Ecto.UUID.generate()
               )

      assert [%OutboxEvent{} = event] = Outbox.pending_for_organization(ctx.organization.id)

      assert event.payload["epcList"] == ["urn:epc:id:sscc:0614141.0123456789"]
    end

    test "replaying the posting key does not enqueue a second event", ctx do
      key = Ecto.UUID.generate()
      items = [delivery_item(ctx, "LOT-EPCIS-2", 5, sscc: "006141411234567890")]

      assert {:ok, _} =
               GoodsReceipts.receive_delivery(ctx.organization.id, ctx.user.id, items, key)

      assert {:ok, _} =
               GoodsReceipts.receive_delivery(ctx.organization.id, ctx.user.id, items, key)

      assert length(Outbox.pending_for_organization(ctx.organization.id)) == 1
    end

    test "an org without a GS1 prefix gets a blocked event, not a pending one" do
      organization = OrganizationsFixtures.organization_fixture()
      user = AccountsFixtures.user_fixture(%{organization_id: organization.id})

      warehouse =
        SitesFixtures.site_fixture(%{
          organization_id: organization.id,
          activities: [:distribution]
        })

      supplier = SuppliersFixtures.supplier_fixture(%{organization_id: organization.id})
      product = ProductsFixtures.product_fixture(%{organization_id: organization.id})

      ctx = %{warehouse: warehouse, supplier: supplier, product: product}

      assert {:ok, _receipt} =
               GoodsReceipts.receive_delivery(
                 organization.id,
                 user.id,
                 [delivery_item(ctx, "LOT-NOPREFIX", 4)],
                 Ecto.UUID.generate()
               )

      assert Outbox.pending_for_organization(organization.id) == []

      assert [%OutboxEvent{status: "blocked"} = event] = Outbox.list_events(organization.id)
      assert event.blocked_reason =~ "GS1 company prefix"
    end
  end

  describe "record_shipment_approval/1 via Distributor.approve_shipment/3" do
    setup do
      organization = DistributorFixtures.distributor_organization_fixture()
      user = AccountsFixtures.user_fixture(%{organization_id: organization.id})
      DistributorFixtures.prepay_allowance_fixture(organization.id, user)

      warehouse = DistributorFixtures.warehouse_fixture(organization.id)

      batch =
        DistributorFixtures.received_unit_fixture(organization.id, warehouse.id, user.id)

      shipment =
        DistributorFixtures.submitted_shipment_fixture(organization.id, user, [batch], %{
          warehouse: warehouse
        })

      %{organization: organization, user: user, shipment: shipment, batch: batch}
    end

    test "approval enqueues packing then shipping in order", ctx do
      assert {:ok, approved} =
               Distributor.approve_shipment(ctx.organization.id, ctx.user, ctx.shipment.id)

      events =
        ctx.organization.id
        |> Outbox.pending_for_organization()
        |> Enum.filter(&(&1.event_type in ["packing", "shipping"]))

      assert [%OutboxEvent{event_type: "packing"} = packing, shipping] = events
      assert shipping.event_type == "shipping"

      assert DateTime.compare(packing.occurred_at, shipping.occurred_at) == :lt

      [shipper] = Repo.preload(approved, :shippers, force: true).shippers
      assert packing.payload["parentID"] =~ shipper.sscc |> String.slice(1..7)
      assert [child_epc] = packing.payload["childEPCs"]
      assert child_epc =~ ctx.batch.serial

      assert [sscc_epc] = shipping.payload["epcList"]
      assert sscc_epc == packing.payload["parentID"]
      assert shipping.payload["disposition"] == "in_transit"

      assert [%{"type" => "desadv", "bizTransaction" => transaction}] =
               shipping.payload["bizTransactionList"]

      assert transaction =~ approved.order_number
    end

    test "every pending event carries a unique urn:uuid eventID", ctx do
      assert {:ok, _} =
               Distributor.approve_shipment(ctx.organization.id, ctx.user, ctx.shipment.id)

      events = Outbox.pending_for_organization(ctx.organization.id)
      ids = Enum.map(events, & &1.payload["eventID"])

      assert Enum.all?(ids, &String.starts_with?(&1, "urn:uuid:"))
      assert length(Enum.uniq(ids)) == length(ids)
    end
  end

  describe "record_facility_receipt/1 via Batches.receive_batch/3" do
    setup do
      organization = DistributorFixtures.distributor_organization_fixture()
      user = AccountsFixtures.user_fixture(%{organization_id: organization.id})

      pharmacy =
        SitesFixtures.site_fixture(%{organization_id: organization.id, activities: [:pharmacy]})

      supplier = SuppliersFixtures.supplier_fixture(%{organization_id: organization.id})
      product = ProductsFixtures.product_fixture(%{organization_id: organization.id})

      %{
        organization: organization,
        user: user,
        pharmacy: pharmacy,
        supplier: supplier,
        product: product
      }
    end

    test "confirming a dispatched batch at a pharmacy enqueues a facility receiving event", ctx do
      {:ok, batch} = pending_batch(ctx, "LOT-F1", 20, sscc: "006141411234567890")

      assert {:ok, _received} = Batches.receive_batch(batch, ctx.user.id)

      events =
        ctx.organization.id
        |> Outbox.list_events()
        |> Enum.filter(&(&1.participant_tier == "facility"))

      assert [%OutboxEvent{} = event] = events
      assert event.event_type == "receiving"
      assert event.status == "pending"
      assert event.source_type == "batch"
      assert event.source_id == batch.id

      assert event.payload["bizStep"] == "receiving"
      assert event.payload["disposition"] == "active"
      assert event.payload["bizLocation"]["id"] =~ "urn:epc:id:sgln:0614141."

      assert [%{"bizTransaction" => recadv}] = event.payload["bizTransactionList"]
      assert recadv =~ "RECV-#{batch.id}"

      assert [%{"source" => source_party}] = event.payload["sourceList"]
      assert source_party =~ "urn:epc:id:sgln:0614141."

      assert event.payload["epcList"] == ["urn:epc:id:sscc:0614141.0123456789"]
    end

    test "a distributor goods receipt does not double-report as facility receiving", ctx do
      warehouse =
        SitesFixtures.site_fixture(%{
          organization_id: ctx.organization.id,
          activities: [:distribution]
        })

      assert {:ok, _receipt} =
               GoodsReceipts.receive_delivery(
                 ctx.organization.id,
                 ctx.user.id,
                 [
                   delivery_item(
                     %{
                       warehouse: warehouse,
                       supplier: ctx.supplier,
                       product: ctx.product
                     },
                     "LOT-NOF1",
                     8,
                     sscc: "006141411234567890"
                   )
                 ],
                 Ecto.UUID.generate()
               )

      assert Outbox.pending_for_organization(ctx.organization.id) != []

      refute Enum.any?(
               Outbox.list_events(ctx.organization.id),
               &(&1.participant_tier == "facility")
             )
    end

    test "receipts at non-pharmacy sites are not reported", ctx do
      warehouse =
        SitesFixtures.site_fixture(%{
          organization_id: ctx.organization.id,
          activities: [:distribution]
        })

      {:ok, batch} =
        pending_batch(%{ctx | pharmacy: warehouse}, "LOT-LAB", 6)

      assert {:ok, _received} = Batches.receive_batch(batch, ctx.user.id)

      assert Outbox.list_events(ctx.organization.id) == []
    end

    test "a pharmacy site without a GLN gets a blocked event", ctx do
      ctx.pharmacy
      |> Ecto.Changeset.change(%{gln: nil})
      |> Repo.update!()

      {:ok, batch} = pending_batch(ctx, "LOT-NOGLN", 3)

      assert {:ok, _received} = Batches.receive_batch(batch, ctx.user.id)
      assert Outbox.pending_for_organization(ctx.organization.id) == []

      assert [%OutboxEvent{status: "blocked", participant_tier: "facility"} = event] =
               Outbox.list_events(ctx.organization.id)

      assert event.blocked_reason =~ "GLN"
    end
  end

  describe "record_dispense/4 via Prescriptions.dispense_item/4" do
    setup do
      organization = DistributorFixtures.distributor_organization_fixture()
      user = AccountsFixtures.user_fixture(%{organization_id: organization.id})
      supplier = SuppliersFixtures.supplier_fixture(%{organization_id: organization.id})
      product = ProductsFixtures.product_fixture(%{organization_id: organization.id})

      visit = PatientVisitsFixtures.patient_visit_fixture(%{organization_id: organization.id})

      {:ok, batch} =
        pending_batch(
          %{
            organization: organization,
            user: user,
            pharmacy: %{id: visit.site_id},
            supplier: supplier,
            product: product
          },
          "LOT-F2",
          20
        )

      {:ok, _received} = Batches.receive_batch(batch, user.id)

      prescription =
        PrescriptionsFixtures.prescription_fixture(%{
          organization_id: organization.id,
          patient_visit_id: visit.id
        })

      item =
        PrescriptionsFixtures.prescription_item_fixture(%{
          organization_id: organization.id,
          prescription_id: prescription.id,
          product_id: product.id,
          quantity_prescribed: 10
        })

      %{
        organization: organization,
        user: user,
        item: item,
        product: product,
        batch: batch
      }
    end

    test "dispensing enqueues a class-level facility dispensing event", ctx do
      assert {:ok, _updated_item} =
               Prescriptions.dispense_item(ctx.organization.id, ctx.item.id, ctx.user.id, 5)

      events =
        ctx.organization.id
        |> Outbox.list_events()
        |> Enum.filter(&(&1.event_type == "dispensing"))

      assert [%OutboxEvent{} = event] = events
      assert event.participant_tier == "facility"
      assert event.status == "pending"
      assert event.source_type == "prescription_item"
      assert event.source_id == ctx.item.id

      assert event.payload["action"] == "OBSERVE"
      assert event.payload["bizStep"] == "dispensing"
      assert event.payload["disposition"] == "dispensed"
      assert event.payload["bizLocation"]["id"] =~ "urn:epc:id:sgln:0614141."
      refute event.payload["epcList"]

      assert [%{"epcClass" => lgtin, "quantity" => 5, "uom" => "EA"}] =
               event.payload["quantityList"]

      assert lgtin =~ "LOT-F2"
    end

    test "dispensing a single serialized unit builds an epcList, not a quantityList", ctx do
      {:ok, batch} =
        Batches.create_batch(ctx.organization.id, %{
          product_id: ctx.product.id,
          site_id: ctx.batch.site_id,
          supplier_id: ctx.batch.supplier_id,
          gtin: ctx.product.gtin,
          batch_no: "LOT-SERIAL",
          serial: "SER-0001",
          expiry_date: ~D[2027-01-01],
          quantity: 1
        })

      {:ok, _received} = Batches.receive_batch(batch, ctx.user.id)

      item =
        PrescriptionsFixtures.prescription_item_fixture(%{
          organization_id: ctx.organization.id,
          prescription_id: ctx.item.prescription_id,
          product_id: ctx.product.id,
          quantity_prescribed: 1
        })

      assert {:ok, _updated_item} =
               Prescriptions.dispense_item(ctx.organization.id, item.id, ctx.user.id, 1)

      events =
        ctx.organization.id
        |> Outbox.list_events()
        |> Enum.filter(&(&1.event_type == "dispensing" and &1.source_id == item.id))

      assert [%OutboxEvent{} = event] = events
      assert event.status == "pending"
      assert [sgtin] = event.payload["epcList"]
      assert sgtin =~ "SER-0001"
      refute Map.has_key?(event.payload, "quantityList")
    end

    test "a serial on a multi-unit batch is never promoted to epcList", ctx do
      {:ok, batch} =
        Batches.create_batch(ctx.organization.id, %{
          product_id: ctx.product.id,
          site_id: ctx.batch.site_id,
          supplier_id: ctx.batch.supplier_id,
          gtin: ctx.product.gtin,
          batch_no: "LOT-MULTI-SERIAL",
          serial: "SER-SHARED",
          expiry_date: ~D[2027-01-01],
          quantity: 3
        })

      {:ok, _received} = Batches.receive_batch(batch, ctx.user.id)

      item =
        PrescriptionsFixtures.prescription_item_fixture(%{
          organization_id: ctx.organization.id,
          prescription_id: ctx.item.prescription_id,
          product_id: ctx.product.id,
          quantity_prescribed: 3
        })

      assert {:ok, _updated_item} =
               Prescriptions.dispense_item(ctx.organization.id, item.id, ctx.user.id, 3)

      events =
        ctx.organization.id
        |> Outbox.list_events()
        |> Enum.filter(&(&1.event_type == "dispensing" and &1.source_id == item.id))

      assert [%OutboxEvent{} = event] = events
      assert event.status == "pending"
      refute Map.has_key?(event.payload, "epcList")
      assert [%{"quantity" => 3}] = event.payload["quantityList"]
    end

    test "an org without a GS1 prefix gets a blocked dispensing event", ctx do
      ctx.organization
      |> Ecto.Changeset.change(%{gs1_company_prefix: nil})
      |> Repo.update!()

      assert {:ok, _updated_item} =
               Prescriptions.dispense_item(ctx.organization.id, ctx.item.id, ctx.user.id, 2)

      events =
        ctx.organization.id
        |> Outbox.list_events()
        |> Enum.filter(&(&1.event_type == "dispensing"))

      assert [%OutboxEvent{status: "blocked"} = event] = events
      assert event.blocked_reason =~ "GS1 company prefix"
    end
  end

  describe "declare_error/3 on a stored event" do
    setup do
      organization = DistributorFixtures.distributor_organization_fixture()
      user = AccountsFixtures.user_fixture(%{organization_id: organization.id})

      warehouse =
        SitesFixtures.site_fixture(%{
          organization_id: organization.id,
          activities: [:distribution]
        })

      supplier = SuppliersFixtures.supplier_fixture(%{organization_id: organization.id})
      product = ProductsFixtures.product_fixture(%{organization_id: organization.id})

      assert {:ok, _receipt} =
               GoodsReceipts.receive_delivery(
                 organization.id,
                 user.id,
                 [
                   delivery_item(
                     %{warehouse: warehouse, supplier: supplier, product: product},
                     "LOT-VOID",
                     6,
                     sscc: "006141411234567890"
                   )
                 ],
                 Ecto.UUID.generate()
               )

      assert [%OutboxEvent{} = original] = Outbox.pending_for_organization(organization.id)

      original =
        original
        |> Ecto.Changeset.change(status: "accepted", http_status: 202)
        |> Repo.update!()

      %{organization: organization, original: original}
    end

    test "enqueues a fresh pending row with the same event_id and a declaration", ctx do
      assert {:ok, void} = Epcis.declare_error(ctx.original, :did_not_occur)

      assert void.id != ctx.original.id
      assert void.event_id == ctx.original.event_id
      assert void.event_type == ctx.original.event_type
      assert void.participant_tier == ctx.original.participant_tier
      assert void.status == "pending"

      assert void.payload["eventID"] == ctx.original.payload["eventID"]
      assert void.payload["bizStep"] == ctx.original.payload["bizStep"]

      assert void.payload["errorDeclaration"]["reason"] == "did_not_occur"

      assert void.payload["errorDeclaration"]["declarationTime"] >
               ctx.original.payload["eventTime"]

      [void_row] = Outbox.pending_for_organization(ctx.organization.id)
      assert void_row.id == void.id
    end

    test "the original row keeps its audit trail untouched", ctx do
      assert {:ok, _void} = Epcis.declare_error(ctx.original, :did_not_occur)

      events = Outbox.list_events(ctx.organization.id, limit: 10)
      [kept] = Enum.take(events, -1)
      assert kept.id == ctx.original.id
      assert kept.status == "accepted"
      assert kept.http_status == 202
      refute kept.payload["errorDeclaration"]
    end

    test "a declaration_time before the original eventTime is bumped past it", ctx do
      {:ok, event_time, 0} = DateTime.from_iso8601(ctx.original.payload["eventTime"])

      assert {:ok, void} =
               Epcis.declare_error(ctx.original, :incorrect_data,
                 declaration_time: ~U[2020-01-01 00:00:00Z]
               )

      expected = event_time |> DateTime.add(1, :second) |> DateTime.truncate(:second)
      assert void.occurred_at == expected

      assert void.payload["errorDeclaration"]["declarationTime"] ==
               DateTime.to_iso8601(expected)
    end

    test "an event the Hub has not stored is refused", ctx do
      {:ok, _receipt} =
        GoodsReceipts.receive_delivery(
          ctx.organization.id,
          AccountsFixtures.user_fixture(%{organization_id: ctx.organization.id}).id,
          [
            delivery_item(
              %{
                warehouse:
                  SitesFixtures.site_fixture(%{
                    organization_id: ctx.organization.id,
                    activities: [:distribution]
                  }),
                supplier:
                  SuppliersFixtures.supplier_fixture(%{organization_id: ctx.organization.id}),
                product: ProductsFixtures.product_fixture(%{organization_id: ctx.organization.id})
              },
              "LOT-PENDING",
              2,
              sscc: "006141411234567890"
            )
          ],
          Ecto.UUID.generate()
        )

      [pending] = Outbox.pending_for_organization(ctx.organization.id)
      assert {:error, :not_stored} = Epcis.declare_error(pending, :did_not_occur)

      events = Outbox.list_events(ctx.organization.id)
      assert Enum.count(events, &(&1.event_type == "receiving")) == 2
      refute Enum.any?(events, &(&1.status == "pending" and &1.payload["errorDeclaration"]))
    end
  end

  defp pending_batch(ctx, lot, quantity, opts \\ []) do
    Batches.create_batch(ctx.organization.id, %{
      product_id: ctx.product.id,
      site_id: ctx.pharmacy.id,
      supplier_id: ctx.supplier.id,
      gtin: ctx.product.gtin,
      batch_no: lot,
      expiry_date: ~D[2030-01-01],
      quantity: quantity,
      sscc: Keyword.get(opts, :sscc)
    })
  end

  defp delivery_item(ctx, batch_no, quantity, opts \\ []) do
    %{
      attrs: %{
        "site_id" => ctx.warehouse.id,
        "supplier_id" => ctx.supplier.id,
        "product_id" => ctx.product.id,
        "gtin" => ctx.product.gtin,
        "batch_no" => batch_no,
        "quantity" => quantity,
        "remaining_quantity" => quantity,
        "expiry_date" => Date.add(Date.utc_today(), 365),
        "cost_per_unit" => "10.00",
        "sscc" => Keyword.get(opts, :sscc)
      }
    }
  end
end
