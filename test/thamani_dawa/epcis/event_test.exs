defmodule ThamaniDawa.Epcis.EventTest do
  use ExUnit.Case, async: true

  alias ThamaniDawa.Epcis.Document
  alias ThamaniDawa.Epcis.Event

  @org_prefix "0614141"
  @gln "0614141000012"
  @supplier_gln "0614141000111"
  @event_id "8b2f91a4-c5d6-43e7-b901-2a3b4c5d6e7f"
  @event_time ~U[2026-11-10 08:30:00Z]

  defp receiving_args(overrides \\ %{}) do
    Map.merge(
      %{
        event_id: @event_id,
        event_time: @event_time,
        org_prefix: @org_prefix,
        biz_location_gln: @gln,
        source_party_gln: @supplier_gln,
        destination_party_gln: @gln,
        grn_number: "GRN-000123",
        ssccs: ["006141411234567890"]
      },
      overrides
    )
  end

  test "receiving builds an ObjectEvent with recadv reference and the SSCC epcList" do
    assert {:ok, event} = Event.receiving(receiving_args())

    assert event["type"] == "ObjectEvent"
    assert event["eventID"] == "urn:uuid:" <> @event_id
    assert event["eventTime"] == "2026-11-10T08:30:00Z"
    assert event["eventTimeZoneOffset"] == "+03:00"
    assert event["action"] == "OBSERVE"
    assert event["bizStep"] == "receiving"
    assert event["disposition"] == "active"
    assert event["epcList"] == ["urn:epc:id:sscc:0614141.0123456789"]
    refute Map.has_key?(event, "quantityList")

    assert event["bizLocation"] == %{"id" => "urn:epc:id:sgln:0614141.00001.0"}

    assert event["bizTransactionList"] == [
             %{
               "type" => "recadv",
               "bizTransaction" => "urn:epcglobal:cbv:bt:0614141:GRN-000123"
             }
           ]

    assert [%{"type" => "owning_party", "source" => "urn:epc:id:sgln:0614141.00011.0"}] =
             event["sourceList"]
  end

  test "receiving without a scanned inbound SSCC is refused — no class-level fallback" do
    assert {:error, :empty_event} = Event.receiving(receiving_args(%{ssccs: []}))
  end

  test "receiving with a missing supplier GLN names the field" do
    assert {:error, {:source_party_gln, :missing}} =
             Event.receiving(receiving_args(%{source_party_gln: nil}))
  end

  test "packing builds an AggregationEvent with SGTIN children" do
    args = %{
      event_id: @event_id,
      event_time: @event_time,
      org_prefix: @org_prefix,
      biz_location_gln: @gln,
      parent_sscc: "006141411234567890",
      children: [
        %{gtin: "00614141107346", serial: "1001"},
        %{gtin: "00614141107346", serial: "1002"}
      ]
    }

    assert {:ok, event} = Event.packing(args)
    assert event["type"] == "AggregationEvent"
    assert event["action"] == "ADD"
    assert event["bizStep"] == "packing"
    assert event["disposition"] == "active"
    assert event["parentID"] == "urn:epc:id:sscc:0614141.0123456789"

    assert event["childEPCs"] == [
             "urn:epc:id:sgtin:0614141.010734.1001",
             "urn:epc:id:sgtin:0614141.010734.1002"
           ]

    refute Map.has_key?(event, "quantityList")

    assert event == %{
             "type" => "AggregationEvent",
             "eventID" => "urn:uuid:" <> @event_id,
             "eventTime" => "2026-11-10T08:30:00Z",
             "eventTimeZoneOffset" => "+03:00",
             "parentID" => "urn:epc:id:sscc:0614141.0123456789",
             "childEPCs" => [
               "urn:epc:id:sgtin:0614141.010734.1001",
               "urn:epc:id:sgtin:0614141.010734.1002"
             ],
             "action" => "ADD",
             "bizStep" => "packing",
             "disposition" => "active",
             "readPoint" => %{"id" => "urn:epc:id:sgln:0614141.00001.0"},
             "bizLocation" => %{"id" => "urn:epc:id:sgln:0614141.00001.0"}
           }
  end

  test "packing a quantity-only case uses quantityList and omits childEPCs" do
    args = %{
      event_id: @event_id,
      event_time: @event_time,
      org_prefix: @org_prefix,
      biz_location_gln: @gln,
      parent_sscc: "006141411234567890",
      quantities: [%{gtin: "00614141107346", lot: "LOT123", quantity: 25, uom: "EA"}]
    }

    assert {:ok, event} = Event.packing(args)
    assert event["action"] == "ADD"
    assert event["bizStep"] == "packing"
    refute Map.has_key?(event, "childEPCs")

    assert event["quantityList"] == [
             %{
               "epcClass" => "urn:epc:class:lgtin:0614141.010734.LOT123",
               "quantity" => 25,
               "uom" => "EA"
             }
           ]
  end

  test "unpack builds a DELETE aggregation for serialized children" do
    args = %{
      event_id: @event_id,
      event_time: @event_time,
      org_prefix: @org_prefix,
      biz_location_gln: @gln,
      parent_sscc: "006141411234567890",
      children: [
        %{gtin: "00614141107346", serial: "1001"},
        %{gtin: "00614141107346", serial: "1002"}
      ]
    }

    assert {:ok, event} = Event.unpack(args)
    assert event["type"] == "AggregationEvent"
    assert event["action"] == "DELETE"
    assert event["bizStep"] == "unpacking"
    assert event["disposition"] == "active"
    assert event["parentID"] == "urn:epc:id:sscc:0614141.0123456789"
    assert event["eventTimeZoneOffset"] == "+03:00"
    refute Map.has_key?(event, "quantityList")

    assert event["childEPCs"] == [
             "urn:epc:id:sgtin:0614141.010734.1001",
             "urn:epc:id:sgtin:0614141.010734.1002"
           ]
  end

  test "unpack of a quantity-only case uses quantityList" do
    args = %{
      event_id: @event_id,
      event_time: @event_time,
      org_prefix: @org_prefix,
      biz_location_gln: @gln,
      parent_sscc: "006141411234567890",
      quantities: [%{gtin: "00614141107346", lot: "LOT123", quantity: 40, uom: "EA"}]
    }

    assert {:ok, event} = Event.unpack(args)
    assert event["action"] == "DELETE"
    assert event["bizStep"] == "unpacking"
    refute Map.has_key?(event, "childEPCs")

    assert event["quantityList"] == [
             %{
               "epcClass" => "urn:epc:class:lgtin:0614141.010734.LOT123",
               "quantity" => 40,
               "uom" => "EA"
             }
           ]
  end

  test "unpack with nothing removed is refused" do
    args = %{
      event_id: @event_id,
      event_time: @event_time,
      org_prefix: @org_prefix,
      biz_location_gln: @gln,
      parent_sscc: "006141411234567890"
    }

    assert {:error, :empty_event} = Event.unpack(args)
  end

  test "shipping builds an ObjectEvent with SSCCs only and desadv reference" do
    args = %{
      event_id: @event_id,
      event_time: @event_time,
      org_prefix: @org_prefix,
      biz_location_gln: @gln,
      destination_gln: @supplier_gln,
      order_number: "PO-2026-0144",
      ssccs: ["006141411234567890"]
    }

    assert {:ok, event} = Event.shipping(args)
    assert event["bizStep"] == "shipping"
    assert event["disposition"] == "in_transit"
    assert event["epcList"] == ["urn:epc:id:sscc:0614141.0123456789"]

    assert event["bizTransactionList"] == [
             %{
               "type" => "desadv",
               "bizTransaction" => "urn:epcglobal:cbv:bt:0614141:PO-2026-0144"
             }
           ]

    assert [
             %{"type" => "owning_party", "destination" => destination},
             %{"type" => "location", "destination" => destination}
           ] = event["destinationList"]
  end

  test "dispensing builds a class-level OBSERVE event with no epcList" do
    args = %{
      event_id: @event_id,
      event_time: @event_time,
      org_prefix: @org_prefix,
      biz_location_gln: @gln,
      quantities: [
        %{gtin: "00614141107346", lot: "LOT12345", quantity: 3, uom: "EA"},
        %{gtin: "00614141000012", lot: "LOT54321", quantity: 2, uom: "EA"}
      ]
    }

    assert {:ok, event} = Event.dispensing(args)

    assert event["type"] == "ObjectEvent"
    assert event["eventID"] == "urn:uuid:" <> @event_id
    assert event["eventTime"] == "2026-11-10T08:30:00Z"
    assert event["eventTimeZoneOffset"] == "+03:00"
    assert event["action"] == "OBSERVE"
    assert event["bizStep"] == "dispensing"
    assert event["disposition"] == "dispensed"
    assert event["readPoint"] == %{"id" => "urn:epc:id:sgln:0614141.00001.0"}
    assert event["bizLocation"] == %{"id" => "urn:epc:id:sgln:0614141.00001.0"}
    refute Map.has_key?(event, "epcList")
    refute Map.has_key?(event, "bizTransactionList")

    assert event["quantityList"] == [
             %{
               "epcClass" => "urn:epc:class:lgtin:0614141.010734.LOT12345",
               "quantity" => 3,
               "uom" => "EA"
             },
             %{
               "epcClass" => "urn:epc:class:lgtin:0614141.000001.LOT54321",
               "quantity" => 2,
               "uom" => "EA"
             }
           ]
  end

  test "dispensing with no quantities is refused" do
    args = %{
      event_id: @event_id,
      event_time: @event_time,
      org_prefix: @org_prefix,
      biz_location_gln: @gln,
      quantities: []
    }

    assert {:error, :empty_event} = Event.dispensing(args)
  end

  test "all-serialized dispensing builds an epcList with no quantityList" do
    args = %{
      event_id: @event_id,
      event_time: @event_time,
      org_prefix: @org_prefix,
      biz_location_gln: @gln,
      epcs: [%{gtin: "00614141107346", serial: "1001"}]
    }

    assert {:ok, event} = Event.dispensing(args)
    assert event["epcList"] == ["urn:epc:id:sgtin:0614141.010734.1001"]
    refute Map.has_key?(event, "quantityList")
  end

  test "commissioning normalizes GTIN-13 values before building EPCIS identifiers" do
    args = %{
      event_id: @event_id,
      event_time: @event_time,
      org_prefix: "6164005",
      biz_location_gln: @gln,
      lot_number: "LOT-1001",
      item_expiration_date: ~D[2028-11-30],
      epcs: [%{gtin: "6164005056517", serial: "1001"}]
    }

    assert {:ok, event} = Event.commission(args)
    assert event["epcList"] == ["urn:epc:id:sgtin:6164005.005651.1001"]
    assert event["ilmd"] == %{"lotNumber" => "LOT-1001", "itemExpirationDate" => "2028-11-30"}
  end

  test "manufacturer pallet packing uses SSCC children and an active disposition" do
    args = %{
      event_id: @event_id,
      event_time: @event_time,
      org_prefix: @org_prefix,
      biz_location_gln: @gln,
      parent_sscc: "006141411234567890",
      sscc_children: ["006141411234567883"]
    }

    assert {:ok, event} = Event.sscc_packing(args)
    assert event["parentID"] == "urn:epc:id:sscc:0614141.0123456789"
    assert event["childEPCs"] == ["urn:epc:id:sscc:0614141.0123456788"]
    assert event["disposition"] == "active"
  end

  test "mixed dispensing carries both epcList and quantityList" do
    args = %{
      event_id: @event_id,
      event_time: @event_time,
      org_prefix: @org_prefix,
      biz_location_gln: @gln,
      epcs: [%{gtin: "00614141107346", serial: "1001"}],
      quantities: [%{gtin: "00614141000012", lot: "LOT54321", quantity: 2, uom: "EA"}]
    }

    assert {:ok, event} = Event.dispensing(args)
    assert event["epcList"] == ["urn:epc:id:sgtin:0614141.010734.1001"]

    assert event["quantityList"] == [
             %{
               "epcClass" => "urn:epc:class:lgtin:0614141.000001.LOT54321",
               "quantity" => 2,
               "uom" => "EA"
             }
           ]
  end

  test "error_declaration clones a stored payload and injects the declaration" do
    {:ok, original} = Event.receiving(receiving_args())
    declaration_time = ~U[2026-11-11 10:00:00Z]

    assert {:ok, amended} =
             Event.error_declaration(original, %{
               declaration_time: declaration_time,
               reason: :did_not_occur
             })

    assert amended["eventID"] == original["eventID"]
    assert amended["bizStep"] == original["bizStep"]
    assert Map.delete(amended, "errorDeclaration") == original

    assert amended["errorDeclaration"] == %{
             "declarationTime" => "2026-11-11T10:00:00Z",
             "reason" => "did_not_occur"
           }
  end

  test "error_declaration with corrective events lists them" do
    {:ok, original} = Event.receiving(receiving_args())

    assert {:ok, amended} =
             Event.error_declaration(original, %{
               declaration_time: ~U[2026-11-11 10:00:00Z],
               reason: "incorrect_data",
               corrective_event_ids: ["urn:uuid:11111111-2222-3333-4444-555555555555"]
             })

    assert amended["errorDeclaration"]["reason"] == "incorrect_data"

    assert amended["errorDeclaration"]["correctiveEventIDs"] == [
             "urn:uuid:11111111-2222-3333-4444-555555555555"
           ]
  end

  test "error_declaration refuses an unknown reason" do
    {:ok, original} = Event.receiving(receiving_args())

    assert {:error, {:reason, :invalid}} =
             Event.error_declaration(original, %{
               declaration_time: ~U[2026-11-11 10:00:00Z],
               reason: "oops"
             })
  end

  test "error_declaration requires declarationTime strictly after eventTime" do
    {:ok, original} = Event.receiving(receiving_args())

    assert {:error, {:declaration_time, :not_after_event_time}} =
             Event.error_declaration(original, %{
               declaration_time: ~U[2026-11-10 08:30:00Z],
               reason: :did_not_occur
             })
  end

  test "error_declaration requires a stored event with eventTime and eventID" do
    assert {:error, {:event_time, :missing}} =
             Event.error_declaration(%{"eventID" => "urn:uuid:8b2f91a4"}, %{
               declaration_time: ~U[2026-11-11 10:00:00Z],
               reason: :did_not_occur
             })

    assert {:error, {:event_id, :missing}} =
             Event.error_declaration(%{"eventTime" => "2026-11-10T08:30:00Z"}, %{
               declaration_time: ~U[2026-11-11 10:00:00Z],
               reason: :did_not_occur
             })
  end

  test "document wraps events in an EPCIS 2.0 envelope" do
    {:ok, event} = Event.receiving(receiving_args())
    document = Document.wrap(event, ~U[2026-11-10 09:00:00Z])

    assert document["@context"] == [
             "https://ref.gs1.org/standards/epcis/epcis-context.jsonld"
           ]

    assert document["type"] == "EPCISDocument"
    assert document["schemaVersion"] == "2.0"
    assert document["creationDate"] == "2026-11-10T09:00:00Z"
    assert document["epcisBody"] == %{"eventList" => [event]}
  end
end
