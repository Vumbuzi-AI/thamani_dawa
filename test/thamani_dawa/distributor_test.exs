defmodule ThamaniDawa.DistributorTest do
  use ThamaniDawa.DataCase, async: true

  import ThamaniDawa.DistributorFixtures

  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Distributor.{Billing, SerialReservation, ShipmentItem, Shipper}

  setup do
    organization = distributor_organization_fixture()
    user = distributor_user_fixture(%{organization_id: organization.id})
    warehouse = warehouse_fixture(organization.id)
    destination = destination_fixture(organization.id)

    %{organization: organization, user: user, warehouse: warehouse, destination: destination}
  end

  defp unit(ctx, attrs \\ %{}),
    do: received_unit_fixture(ctx.organization.id, ctx.warehouse.id, ctx.user.id, attrs)

  defp draft(ctx, attrs \\ %{}) do
    shipment_fixture(
      ctx.organization.id,
      ctx.user,
      Map.merge(%{warehouse: ctx.warehouse, destination: ctx.destination}, attrs)
    )
  end

  defp claimed_draft_with_shipper(ctx) do
    shipment = draft(ctx)
    mobile_user = mobile_user_fixture(ctx.organization.id)
    {:ok, _} = Distributor.select_shipment(mobile_user, shipment.id)
    {:ok, shipper} = Distributor.create_shipper(mobile_user, shipment.id, %{})
    {shipment, mobile_user, shipper}
  end

  describe "create_shipment/3" do
    test "snapshots the origin site and resolved destination", ctx do
      shipment = draft(ctx)

      assert shipment.status == "draft"
      assert shipment.origin_company == ctx.warehouse.name
      assert shipment.destination_company == ctx.destination.name
      assert shipment.destination_site_id == ctx.destination.id
      assert "SHP-" <> _ = shipment.reference
    end

    test "resolves a destination belonging to a different organization's site", ctx do
      other = distributor_organization_fixture()
      foreign_destination = destination_fixture(other.id)

      assert {:ok, shipment} =
               Distributor.create_shipment(ctx.organization.id, ctx.user, %{
                 "order_number" => "PO-1",
                 "origin_gln" => ctx.warehouse.gln,
                 "destination_gln" => foreign_destination.gln
               })

      assert shipment.destination_company == foreign_destination.name
    end

    test "rejects a destination GLN that cannot be verified", ctx do
      assert {:error, changeset} =
               Distributor.create_shipment(ctx.organization.id, ctx.user, %{
                 "order_number" => "PO-1",
                 "origin_gln" => ctx.warehouse.gln,
                 "destination_gln" => "0000000000000"
               })

      assert "could not be verified — check the GLN" in errors_on(changeset).destination_gln
    end

    test "requires different origin and destination GLNs", ctx do
      assert {:error, changeset} =
               Distributor.create_shipment(ctx.organization.id, ctx.user, %{
                 "order_number" => "PO-1",
                 "origin_gln" => ctx.warehouse.gln,
                 "destination_gln" => ctx.warehouse.gln
               })

      assert "must be different from the origin GLN" in errors_on(changeset).destination_gln
    end
  end

  describe "list_shipments/2 origin_site_id filter" do
    test "narrows to shipments originating from the given warehouse", ctx do
      other_warehouse = warehouse_fixture(ctx.organization.id)
      from_default = draft(ctx)
      from_other = draft(ctx, %{warehouse: other_warehouse})

      result =
        Distributor.list_shipments(ctx.organization.id, %{origin_site_id: ctx.warehouse.id})

      ids = Enum.map(result.entries, & &1.id)

      assert from_default.id in ids
      refute from_other.id in ids
    end

    test "returns every shipment when no origin_site_id is given", ctx do
      other_warehouse = warehouse_fixture(ctx.organization.id)
      from_default = draft(ctx)
      from_other = draft(ctx, %{warehouse: other_warehouse})

      result = Distributor.list_shipments(ctx.organization.id, %{})
      ids = Enum.map(result.entries, & &1.id)

      assert from_default.id in ids
      assert from_other.id in ids
    end
  end

  describe "select_shipment/2" do
    test "claims an unclaimed draft once, and refuses other mobile users", ctx do
      shipment = draft(ctx)
      first = mobile_user_fixture(ctx.organization.id)
      second = mobile_user_fixture(ctx.organization.id)

      assert {:ok, claimed} = Distributor.select_shipment(first, shipment.id)
      assert claimed.assigned_mobile_user_id == first.id
      assert {:unchanged, _} = Distributor.select_shipment(first, shipment.id)
      assert {:error, :already_assigned} = Distributor.select_shipment(second, shipment.id)
    end

    test "can't reach another organization's shipment", ctx do
      shipment = draft(ctx)
      outsider = mobile_user_fixture(distributor_organization_fixture().id)

      assert {:error, :not_found} = Distributor.select_shipment(outsider, shipment.id)
    end
  end

  describe "scan_item/3" do
    test "records a known unit as ok with catalogue product details", ctx do
      batch = unit(ctx)
      {shipment, mobile_user, shipper} = claimed_draft_with_shipper(ctx)

      assert {:ok, %ShipmentItem{} = item} =
               Distributor.scan_item(mobile_user, shipper.id, %{
                 "raw_data_matrix" => data_matrix_for(batch)
               })

      assert item.shipment_id == shipment.id
      assert item.validation_status == "ok"
      assert item.product_source == "catalogue"
      assert item.batch_id == batch.id
    end

    test "flags a serial no received batch carries as unknown_serial", ctx do
      batch = unit(ctx)
      {_shipment, mobile_user, shipper} = claimed_draft_with_shipper(ctx)
      raw = data_matrix_for(%{batch | serial: "NEVER-RECEIVED"})

      assert {:ok, item} =
               Distributor.scan_item(mobile_user, shipper.id, %{"raw_data_matrix" => raw})

      assert item.validation_status == "unknown_serial"
    end

    test "flags a known serial with a different batch number as data_mismatch", ctx do
      batch = unit(ctx)
      {_shipment, mobile_user, shipper} = claimed_draft_with_shipper(ctx)
      raw = data_matrix_for(%{batch | batch_no: "OTHERLOT"})

      assert {:ok, item} =
               Distributor.scan_item(mobile_user, shipper.id, %{"raw_data_matrix" => raw})

      assert item.validation_status == "data_mismatch"
    end

    test "rejects a duplicate scan within the shipment", ctx do
      batch = unit(ctx)
      {_shipment, mobile_user, shipper} = claimed_draft_with_shipper(ctx)
      attrs = %{"raw_data_matrix" => data_matrix_for(batch)}

      assert {:ok, _} = Distributor.scan_item(mobile_user, shipper.id, attrs)
      assert {:error, :duplicate_scan} = Distributor.scan_item(mobile_user, shipper.id, attrs)
    end

    test "rejects a scan whose client-parsed fields disagree with the server", ctx do
      batch = unit(ctx)
      {_shipment, mobile_user, shipper} = claimed_draft_with_shipper(ctx)

      assert {:error, :parsed_mismatch} =
               Distributor.scan_item(mobile_user, shipper.id, %{
                 "raw_data_matrix" => data_matrix_for(batch),
                 "serial" => "SOMETHING-ELSE"
               })
    end

    test "rejects scans from a mobile user who doesn't hold the draft", ctx do
      batch = unit(ctx)
      {_shipment, _holder, shipper} = claimed_draft_with_shipper(ctx)
      other = mobile_user_fixture(ctx.organization.id)

      assert {:error, :not_assigned} =
               Distributor.scan_item(other, shipper.id, %{
                 "raw_data_matrix" => data_matrix_for(batch)
               })
    end
  end

  describe "submit_shipment/2" do
    test "reserves every scanned serial and moves to submitted", ctx do
      batch = unit(ctx)

      shipment =
        submitted_shipment_fixture(ctx.organization.id, ctx.user, [batch], %{
          warehouse: ctx.warehouse,
          destination: ctx.destination
        })

      assert shipment.status == "submitted"
      assert Repo.get_by(SerialReservation, barcode: batch.gtin, serial: batch.serial)
    end

    test "refuses a shipment with an empty shipper", ctx do
      {shipment, mobile_user, _shipper} = claimed_draft_with_shipper(ctx)

      assert {:error, {:invalid, problems}} =
               Distributor.submit_shipment(mobile_user, shipment.id)

      assert Enum.any?(problems, &(&1.code == :empty_shipper))
    end

    test "refuses a unit already held by another submitted shipment", ctx do
      batch = unit(ctx)

      _first =
        submitted_shipment_fixture(ctx.organization.id, ctx.user, [batch], %{
          warehouse: ctx.warehouse,
          destination: ctx.destination
        })

      {_shipment, mobile_user, shipper} = claimed_draft_with_shipper(ctx)

      assert {:error, :serial_already_shipped} =
               Distributor.scan_item(mobile_user, shipper.id, %{
                 "raw_data_matrix" => data_matrix_for(batch)
               })
    end

    test "refuses unknown serials that have no received batch", ctx do
      batch = unit(ctx)
      {_shipment, mobile_user, shipper} = claimed_draft_with_shipper(ctx)
      raw = data_matrix_for(%{batch | serial: "NEVER-RECEIVED"})

      assert {:ok, item} =
               Distributor.scan_item(mobile_user, shipper.id, %{"raw_data_matrix" => raw})

      assert item.validation_status == "unknown_serial"
      assert is_nil(item.batch_id)

      assert {:error, {:invalid, problems}} =
               Distributor.submit_shipment(mobile_user, item.shipment_id)

      assert Enum.any?(problems, &(&1.code == :unknown_unit))
    end
  end

  describe "approve_shipment/3" do
    setup ctx do
      prepay_allowance_fixture(ctx.organization.id, ctx.user, 100)
      :ok
    end

    test "issues one SSCC per shipper, charges the allowance, and commits reservations", ctx do
      batch = unit(ctx)

      shipment =
        submitted_shipment_fixture(ctx.organization.id, ctx.user, [batch], %{
          warehouse: ctx.warehouse,
          destination: ctx.destination
        })

      assert {:ok, approved} =
               Distributor.approve_shipment(ctx.organization.id, ctx.user, shipment.id)

      assert approved.status == "approved"

      [shipper] = Repo.all(from s in Shipper, where: s.shipment_id == ^shipment.id)
      assert String.length(shipper.sscc) == 18
      assert shipper.gtin == batch.gtin
      assert shipper.unit_count == 1

      [request] = ThamaniDawa.GS1.MemberApiStub.create_requests()
      assert hd(request["batch_info"])["gtin"] == batch.gtin
      assert hd(request["batch_info"])["batch"] == batch.batch_no
      assert request["address"]["from_address"]
      assert request["address"]["to_address"]
      assert request["count_of_trade_items"] == 1

      assert Repo.get_by!(SerialReservation, shipment_id: shipment.id).committed_at
      assert Billing.active_usage(ctx.organization.id).running_quantity == 1
    end

    test "depletes remaining stock from scanned units and moves an empty batch to dispatch",
         ctx do
      batch = unit(ctx) |> Ecto.Changeset.change(remaining_quantity: 1) |> Repo.update!()

      shipment =
        submitted_shipment_fixture(ctx.organization.id, ctx.user, [batch], %{
          warehouse: ctx.warehouse,
          destination: ctx.destination
        })

      assert {:ok, _} = Distributor.approve_shipment(ctx.organization.id, ctx.user, shipment.id)

      updated = Repo.get!(Batch, batch.id)
      assert updated.remaining_quantity == 0
      assert updated.zone == :dispatch
    end

    test "leaves remaining stock in place when a batch is only partly shipped", ctx do
      batch = unit(ctx)
      assert batch.remaining_quantity == 10

      shipment =
        submitted_shipment_fixture(ctx.organization.id, ctx.user, [batch], %{
          warehouse: ctx.warehouse,
          destination: ctx.destination
        })

      assert {:ok, _} = Distributor.approve_shipment(ctx.organization.id, ctx.user, shipment.id)

      updated = Repo.get!(Batch, batch.id)
      assert updated.remaining_quantity == 9
      assert updated.zone == :receiving
    end

    test "fails :reservation_missing when serial reservations are gone", ctx do
      shipment =
        submitted_shipment_fixture(ctx.organization.id, ctx.user, [unit(ctx)], %{
          warehouse: ctx.warehouse,
          destination: ctx.destination
        })

      Repo.delete_all(from r in SerialReservation, where: r.shipment_id == ^shipment.id)

      assert {:error, :reservation_missing} =
               Distributor.approve_shipment(ctx.organization.id, ctx.user, shipment.id)
    end

    test "refuses to re-ship a serial that was already approved", ctx do
      batch = unit(ctx)

      shipment =
        submitted_shipment_fixture(ctx.organization.id, ctx.user, [batch], %{
          warehouse: ctx.warehouse,
          destination: ctx.destination
        })

      assert {:ok, _} = Distributor.approve_shipment(ctx.organization.id, ctx.user, shipment.id)

      {_second, mobile_user, shipper} = claimed_draft_with_shipper(ctx)

      assert {:error, :serial_already_shipped} =
               Distributor.scan_item(mobile_user, shipper.id, %{
                 "raw_data_matrix" => data_matrix_for(batch)
               })
    end

    test "is idempotent", ctx do
      shipment =
        submitted_shipment_fixture(ctx.organization.id, ctx.user, [unit(ctx)], %{
          warehouse: ctx.warehouse,
          destination: ctx.destination
        })

      assert {:ok, _} = Distributor.approve_shipment(ctx.organization.id, ctx.user, shipment.id)

      assert {:already_approved, _} =
               Distributor.approve_shipment(ctx.organization.id, ctx.user, shipment.id)

      assert Billing.active_usage(ctx.organization.id).running_quantity == 1
    end

    test "issues an SSCC from GS1 without a local company prefix", ctx do
      before = ctx.organization.next_sscc_serial

      ctx.organization
      |> Ecto.Changeset.change(gs1_company_prefix: nil)
      |> Repo.update!()

      shipment =
        submitted_shipment_fixture(ctx.organization.id, ctx.user, [unit(ctx)], %{
          warehouse: ctx.warehouse,
          destination: ctx.destination
        })

      assert {:ok, _} = Distributor.approve_shipment(ctx.organization.id, ctx.user, shipment.id)

      [shipper] = Repo.all(from s in Shipper, where: s.shipment_id == ^shipment.id)
      assert shipper.sscc =~ ~r/^\d{18}$/

      assert Repo.get!(ctx.organization.__struct__, ctx.organization.id).next_sscc_serial ==
               before
    end

    test "rolls the approval back when GS1 cannot issue an SSCC", ctx do
      ThamaniDawa.GS1.MemberApiStub.fail_next(:unavailable)

      shipment =
        submitted_shipment_fixture(ctx.organization.id, ctx.user, [unit(ctx)], %{
          warehouse: ctx.warehouse,
          destination: ctx.destination
        })

      assert {:error, {:gs1, :unavailable}} =
               Distributor.approve_shipment(ctx.organization.id, ctx.user, shipment.id)

      [shipper] = Repo.all(from s in Shipper, where: s.shipment_id == ^shipment.id)
      assert is_nil(shipper.sscc)
      assert Billing.active_usage(ctx.organization.id).running_quantity == 0
    end
  end

  describe "lookup_shipper_by_sscc/1" do
    test "returns the serials GS1 has recorded for the case" do
      sscc = "061600000000000018"

      ThamaniDawa.GS1.MemberApiStub.put_contents(sscc, [
        %{
          "gtin" => "06141411234567",
          "name" => "Amoxicillin",
          "batches" => [
            %{
              "batch" => "LOT-1",
              "production_date" => "2026-01-15",
              "expiry_date" => "2027-06-01",
              "serials" => [%{"serial" => "SN-1"}, %{"serial" => "SN-2"}]
            }
          ]
        }
      ])

      assert {:ok, shipper} = Distributor.lookup_shipper_by_sscc(sscc)
      assert Enum.map(shipper.items, & &1.serial) == ["SN-1", "SN-2"]
      assert hd(shipper.items).gtin == "06141411234567"
      assert hd(shipper.items).batch == "LOT-1"
      assert hd(shipper.items).expiry_date == ~D[2027-06-01]
      assert {:error, :not_found} = Distributor.lookup_shipper_by_sscc("000000000000000000")
    end
  end

  describe "approve_shipment/3 without allowance" do
    test "fails with a billing error when no plan is active", ctx do
      shipment =
        submitted_shipment_fixture(ctx.organization.id, ctx.user, [unit(ctx)], %{
          warehouse: ctx.warehouse,
          destination: ctx.destination
        })

      assert {:error, {:billing, :no_active_plan}} =
               Distributor.approve_shipment(ctx.organization.id, ctx.user, shipment.id)
    end
  end

  describe "reject_shipment/4 and reopen_shipment/2" do
    test "rejecting releases reservations; reopening returns to draft", ctx do
      batch = unit(ctx)
      mobile_user = mobile_user_fixture(ctx.organization.id)

      shipment =
        submitted_shipment_fixture(ctx.organization.id, ctx.user, [batch], %{
          warehouse: ctx.warehouse,
          destination: ctx.destination,
          mobile_user: mobile_user
        })

      assert {:error, :reason_required} =
               Distributor.reject_shipment(ctx.organization.id, ctx.user, shipment.id, " ")

      assert {:ok, rejected} =
               Distributor.reject_shipment(ctx.organization.id, ctx.user, shipment.id, "Expired")

      assert rejected.status == "rejected"
      refute Repo.get_by(SerialReservation, shipment_id: shipment.id)

      assert {:ok, reopened} = Distributor.reopen_shipment(mobile_user, shipment.id)
      assert reopened.status == "draft"
    end
  end

  describe "remove_item/4" do
    test "deletes the unit and its reservation from a submitted shipment", ctx do
      batch = unit(ctx)

      shipment =
        submitted_shipment_fixture(ctx.organization.id, ctx.user, [batch], %{
          warehouse: ctx.warehouse,
          destination: ctx.destination
        })

      item = Repo.get_by!(ShipmentItem, shipment_id: shipment.id)

      assert {:ok, _} =
               Distributor.remove_item(ctx.organization.id, ctx.user, shipment.id, item.id)

      refute Repo.get(ShipmentItem, item.id)
      refute Repo.get_by(SerialReservation, shipment_id: shipment.id)
    end
  end

  describe "mobile users" do
    test "create_mobile_user/2 emails a PIN and stores only its hash", ctx do
      mobile_user = mobile_user_fixture(ctx.organization.id)

      assert mobile_user.pin_hash
      refute Map.has_key?(mobile_user, :pin)
    end

    test "deactivating revokes app access", ctx do
      mobile_user = mobile_user_fixture(ctx.organization.id)

      assert {:ok, inactive} = Distributor.set_mobile_user_active(mobile_user, false)
      refute inactive.active
    end
  end
end
