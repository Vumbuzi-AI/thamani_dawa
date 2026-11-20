defmodule ThamaniDawa.Distributor.ReportsTest do
  use ThamaniDawa.DataCase, async: true

  import ThamaniDawa.DistributorFixtures

  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Distributor.Reports

  setup do
    organization = distributor_organization_fixture()
    user = distributor_user_fixture(%{organization_id: organization.id})
    warehouse = warehouse_fixture(organization.id)
    destination = destination_fixture(organization.id)
    prepay_allowance_fixture(organization.id, user, 100)

    %{organization: organization, user: user, warehouse: warehouse, destination: destination}
  end

  defp unit(ctx, attrs \\ %{}),
    do: received_unit_fixture(ctx.organization.id, ctx.warehouse.id, ctx.user.id, attrs)

  describe "shipper_labels/1" do
    test "includes the material description and sorted serials packed into each shipper", ctx do
      first = unit(ctx, %{serial: "SN-B"})
      second = unit(ctx, %{serial: "SN-A", product: first.product})

      shipment =
        shipment_fixture(ctx.organization.id, ctx.user, %{
          warehouse: ctx.warehouse,
          destination: ctx.destination
        })

      mobile_user = mobile_user_fixture(ctx.organization.id)
      {:ok, _} = Distributor.select_shipment(mobile_user, shipment.id)

      {:ok, shipper} =
        Distributor.create_shipper(mobile_user, shipment.id, %{
          "material_description" => "Paracetamol 500mg"
        })

      Enum.each([first, second], fn batch ->
        {:ok, _item} =
          Distributor.scan_item(mobile_user, shipper.id, %{
            "raw_data_matrix" => data_matrix_for(batch)
          })
      end)

      {:ok, shipment} = Distributor.submit_shipment(mobile_user, shipment.id)
      {:ok, _approved} = Distributor.approve_shipment(ctx.organization.id, ctx.user, shipment.id)
      approved = Distributor.get_shipment!(ctx.organization.id, shipment.id)

      [label] = Reports.shipper_labels(approved)

      assert label.material_description == "Paracetamol 500mg"
      assert label.serials == ["SN-A", "SN-B"]
      assert label.unit_count == 2
    end

    test "returns an empty list for a shipment that hasn't been approved", ctx do
      shipment =
        submitted_shipment_fixture(ctx.organization.id, ctx.user, [unit(ctx)], %{
          warehouse: ctx.warehouse,
          destination: ctx.destination
        })

      assert Reports.shipper_labels(shipment) == []
    end
  end
end
