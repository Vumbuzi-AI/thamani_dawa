defmodule ThamaniDawa.DistributorTest do
  use ThamaniDawa.DataCase, async: true

  import ThamaniDawa.DistributorFixtures

  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Distributor.{Billing, SerialReservation, ShipmentItem, Shipper}

  setup do
    organization = distributor_organization_fixture()
    user = distributor_user_fixture(%{organization_id: organization.id})
    warehouse = warehouse_fixture(organization.id)
    customer = customer_fixture(organization.id)

    %{organization: organization, user: user, warehouse: warehouse, customer: customer}
  end

  defp unit(ctx, attrs \\ %{}),
    do: received_unit_fixture(ctx.organization.id, ctx.warehouse.id, ctx.user.id, attrs)

  defp draft(ctx, attrs \\ %{}) do
    shipment_fixture(
      ctx.organization.id,
      ctx.user,
      Map.merge(%{warehouse: ctx.warehouse, customer: ctx.customer}, attrs)
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
    test "snapshots the origin site and destination customer", ctx do
      shipment = draft(ctx)

      assert shipment.status == "draft"
      assert shipment.origin_company == ctx.warehouse.name
      assert shipment.destination_company == ctx.customer.name
      assert shipment.destination_po_box == ctx.customer.po_box
      assert "SHP-" <> _ = shipment.reference
    end

    test "rejects GLNs that aren't the organization's own site or customer", ctx do
      other = distributor_organization_fixture()
      foreign_customer = customer_fixture(other.id)

      assert {:error, changeset} =
               Distributor.create_shipment(ctx.organization.id, ctx.user, %{
                 "order_number" => "PO-1",
                 "origin_gln" => ctx.warehouse.gln,
                 "destination_gln" => foreign_customer.gln
               })

      assert "is not one of your active customers" in errors_on(changeset).destination_gln
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
          customer: ctx.customer
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
          customer: ctx.customer
        })

      {_shipment, mobile_user, shipper} = claimed_draft_with_shipper(ctx)

      assert {:error, :serial_already_shipped} =
               Distributor.scan_item(mobile_user, shipper.id, %{
                 "raw_data_matrix" => data_matrix_for(batch)
               })
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
          customer: ctx.customer
        })

      assert {:ok, approved} =
               Distributor.approve_shipment(ctx.organization.id, ctx.user, shipment.id)

      assert approved.status == "approved"

      [shipper] = Repo.all(from s in Shipper, where: s.shipment_id == ^shipment.id)
      assert String.length(shipper.sscc) == 18
      assert shipper.gtin == batch.gtin
      assert shipper.unit_count == 1

      assert Repo.get_by!(SerialReservation, shipment_id: shipment.id).committed_at
      assert Billing.active_usage(ctx.organization.id).running_quantity == 1
    end

    test "is idempotent", ctx do
      shipment =
        submitted_shipment_fixture(ctx.organization.id, ctx.user, [unit(ctx)], %{
          warehouse: ctx.warehouse,
          customer: ctx.customer
        })

      assert {:ok, _} = Distributor.approve_shipment(ctx.organization.id, ctx.user, shipment.id)

      assert {:already_approved, _} =
               Distributor.approve_shipment(ctx.organization.id, ctx.user, shipment.id)

      assert Billing.active_usage(ctx.organization.id).running_quantity == 1
    end

    test "fails without a GS1 Company Prefix", ctx do
      shipment =
        submitted_shipment_fixture(ctx.organization.id, ctx.user, [unit(ctx)], %{
          warehouse: ctx.warehouse,
          customer: ctx.customer
        })

      ctx.organization
      |> Ecto.Changeset.change(gs1_company_prefix: nil)
      |> Repo.update!()

      assert {:error, :missing_gs1_company_prefix} =
               Distributor.approve_shipment(ctx.organization.id, ctx.user, shipment.id)
    end
  end

  describe "approve_shipment/3 without allowance" do
    test "fails with a billing error when no plan is active", ctx do
      shipment =
        submitted_shipment_fixture(ctx.organization.id, ctx.user, [unit(ctx)], %{
          warehouse: ctx.warehouse,
          customer: ctx.customer
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
          customer: ctx.customer,
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
          customer: ctx.customer
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
