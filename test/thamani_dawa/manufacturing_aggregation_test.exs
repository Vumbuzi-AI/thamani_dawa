defmodule ThamaniDawa.ManufacturingAggregationTest do
  use ThamaniDawa.DataCase, async: true

  import ThamaniDawa.ManufacturerFixtures

  alias ThamaniDawa.Epcis.Outbox
  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Manufacturing.Aggregation
  alias ThamaniDawa.Manufacturing.AggregationItem
  alias ThamaniDawa.Manufacturing.Serial
  alias ThamaniDawa.Manufacturing.ShipperSscc
  alias ThamaniDawa.Manufacturing.SsccBatch
  alias ThamaniDawa.Repo

  setup do
    organization = manufacturer_organization_fixture()
    site = manufacturing_site_fixture(organization.id)
    user = manufacturer_user_fixture(%{organization_id: organization.id, site_id: site.id})
    product = manufacturer_product_fixture(organization.id)
    batch = manufacturer_batch_fixture(organization.id, product.id)
    other_batch = manufacturer_batch_fixture(organization.id, product.id)

    sscc = insert_sscc(organization.id, product.gtin, site.gln, 5)
    link_batch(sscc, batch)

    ok_serial = insert_serial(organization.id, product, batch, "S-OK-1")
    wrong_serial = insert_serial(organization.id, product, other_batch, "S-WRONG-1")

    other_sscc = insert_sscc(organization.id, product.gtin, site.gln, 5)

    aggregated_serial =
      insert_serial(organization.id, product, batch, "S-AGG-1", %{
        manufacturer_shipper_sscc_id: other_sscc.id
      })

    %{
      organization: organization,
      user: user,
      product: product,
      batch: batch,
      other_batch: other_batch,
      sscc: sscc,
      ok_serial: ok_serial,
      wrong_serial: wrong_serial,
      aggregated_serial: aggregated_serial
    }
  end

  describe "classify_serial/3" do
    test "returns each classification branch", %{
      organization: organization,
      sscc: sscc,
      ok_serial: ok_serial,
      wrong_serial: wrong_serial,
      aggregated_serial: aggregated_serial
    } do
      assert {"ok", %Serial{id: id}} =
               Manufacturing.classify_serial(organization.id, sscc, "  #{ok_serial.serial}  ")

      assert id == ok_serial.id

      assert {"unknown_serial", nil} =
               Manufacturing.classify_serial(organization.id, sscc, "NOT-A-SERIAL")

      assert {"wrong_batch", %Serial{id: wrong_id}} =
               Manufacturing.classify_serial(organization.id, sscc, wrong_serial.serial)

      assert wrong_id == wrong_serial.id

      assert {"already_aggregated", %Serial{id: aggregated_id}} =
               Manufacturing.classify_serial(organization.id, sscc, aggregated_serial.serial)

      assert aggregated_id == aggregated_serial.id
    end

    test "a serial already linked to the same SSCC is ok", %{
      organization: organization,
      product: product,
      batch: batch,
      sscc: sscc
    } do
      serial =
        insert_serial(organization.id, product, batch, "S-SAME-1", %{
          manufacturer_shipper_sscc_id: sscc.id
        })

      assert {"ok", %Serial{id: id}} =
               Manufacturing.classify_serial(organization.id, sscc, serial.serial)

      assert id == serial.id
    end
  end

  describe "scan flow" do
    test "creates, scans, submits, and approves an aggregation", %{
      organization: organization,
      user: user,
      product: product,
      sscc: sscc,
      ok_serial: ok_serial
    } do
      assert {:ok, aggregation} = Manufacturing.create_aggregation(organization.id, user, sscc.id)
      assert aggregation.status == "draft"
      assert String.starts_with?(aggregation.reference, "MAG-")

      assert {:ok, item} =
               Manufacturing.scan_aggregation_item(organization.id, aggregation, ok_serial.serial)

      assert item.validation_status == "ok"
      assert item.serial == ok_serial.serial
      assert item.gtin == product.gtin
      assert item.manufacturer_serial_id == ok_serial.id

      assert {:ok, submitted} = Manufacturing.submit_aggregation(organization.id, aggregation.id)
      assert submitted.status == "submitted"
      assert submitted.submitted_at

      assert {:ok, approved} =
               Manufacturing.approve_aggregation(organization.id, user, aggregation.id)

      assert approved.status == "approved"
      assert approved.approved_at
      assert approved.approved_by_id == user.id

      serial = Repo.get!(Serial, ok_serial.id)
      assert serial.manufacturer_shipper_sscc_id == sscc.id

      event = Enum.find(Outbox.list_events(organization.id), &(&1.event_type == "packing"))
      assert event
      assert event.participant_tier == "manufacturer"
      assert event.source_type == "manufacturer_shipper_sscc"
      assert event.source_id == sscc.id
      assert event.payload["bizStep"] == "packing"
      assert [child] = event.payload["childEPCs"]
      assert child =~ ok_serial.serial
    end

    test "create_submitted_aggregation/4 scans and submits in one step", %{
      organization: organization,
      user: user,
      sscc: sscc,
      ok_serial: ok_serial
    } do
      assert {:ok, aggregation} =
               Manufacturing.create_submitted_aggregation(organization.id, user, sscc.id, [
                 ok_serial.serial
               ])

      assert aggregation.status == "submitted"
      assert aggregation.submitted_at
      assert [%AggregationItem{serial: serial, validation_status: "ok"}] = aggregation.items
      assert serial == ok_serial.serial
    end

    test "approval rolls back when any item is not ok", %{
      organization: organization,
      user: user,
      sscc: sscc
    } do
      assert {:ok, aggregation} = Manufacturing.create_aggregation(organization.id, user, sscc.id)

      assert {:ok, item} =
               Manufacturing.scan_aggregation_item(organization.id, aggregation, "NOPE")

      assert item.validation_status == "unknown_serial"

      assert {:ok, _submitted} = Manufacturing.submit_aggregation(organization.id, aggregation.id)

      assert {:error, {:invalid, invalid_items}} =
               Manufacturing.approve_aggregation(organization.id, user, aggregation.id)

      assert [%AggregationItem{id: id}] = invalid_items
      assert id == item.id
      assert Repo.get!(Aggregation, aggregation.id).status == "submitted"
    end

    test "approval rolls back when the SSCC would exceed capacity", %{
      organization: organization,
      user: user,
      product: product,
      batch: batch
    } do
      sscc = insert_sscc(organization.id, product.gtin, "0614141000012", 1)
      link_batch(sscc, batch)

      first = insert_serial(organization.id, product, batch, "CAP-1")
      second = insert_serial(organization.id, product, batch, "CAP-2")

      assert {:ok, aggregation} =
               Manufacturing.create_submitted_aggregation(organization.id, user, sscc.id, [
                 first.serial,
                 second.serial
               ])

      assert {:error, {:over_capacity, %{capacity: 1}}} =
               Manufacturing.approve_aggregation(organization.id, user, aggregation.id)

      assert Repo.get!(Serial, first.id).manufacturer_shipper_sscc_id == nil
      assert Repo.get!(Serial, second.id).manufacturer_shipper_sscc_id == nil
      assert Repo.get!(Aggregation, aggregation.id).status == "submitted"
    end

    test "reject_aggregation/4 records the reason and reviewer", %{
      organization: organization,
      user: user,
      sscc: sscc,
      ok_serial: ok_serial
    } do
      assert {:ok, aggregation} =
               Manufacturing.create_submitted_aggregation(organization.id, user, sscc.id, [
                 ok_serial.serial
               ])

      assert {:ok, rejected} =
               Manufacturing.reject_aggregation(
                 organization.id,
                 user,
                 aggregation.id,
                 "Wrong batch"
               )

      assert rejected.status == "rejected"
      assert rejected.rejection_reason == "Wrong batch"
      assert rejected.rejected_at
      assert rejected.rejected_by_id == user.id
    end
  end

  describe "list_aggregations/2" do
    test "filters by status and searches by reference", %{
      organization: organization,
      user: user,
      sscc: sscc,
      ok_serial: ok_serial
    } do
      assert {:ok, aggregation} =
               Manufacturing.create_submitted_aggregation(organization.id, user, sscc.id, [
                 ok_serial.serial
               ])

      assert %{total_entries: 1, entries: [entry]} =
               Manufacturing.list_aggregations(organization.id, %{status: "submitted"})

      assert entry.id == aggregation.id
      assert entry.item_count == 1

      assert %{total_entries: 0} =
               Manufacturing.list_aggregations(organization.id, %{search: "nothing-matches"})
    end
  end

  defp insert_sscc(organization_id, gtin, from_gln, capacity) do
    number = rem(System.unique_integer([:positive]), 1_000_000_000)
    suffix = number |> Integer.to_string() |> String.pad_leading(9, "0")
    body = "06160000" <> suffix
    code = body <> Integer.to_string(ThamaniDawa.GS1.Sscc.mod10_check_digit(body))

    Repo.insert!(%ShipperSscc{
      organization_id: organization_id,
      code: code,
      gtin: gtin,
      from_gln: from_gln,
      count_of_trade_items: capacity
    })
  end

  defp link_batch(sscc, batch) do
    Repo.insert!(%SsccBatch{
      manufacturer_shipper_sscc_id: sscc.id,
      manufacturer_batch_id: batch.id
    })

    sscc
  end

  defp insert_serial(organization_id, product, batch, serial, attrs \\ %{}) do
    Repo.insert!(
      struct(
        %Serial{
          organization_id: organization_id,
          manufacturer_product_id: product.id,
          manufacturer_batch_id: batch.id,
          serial: serial
        },
        attrs
      )
    )
  end
end
