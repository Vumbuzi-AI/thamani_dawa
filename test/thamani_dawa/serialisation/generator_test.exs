defmodule ThamaniDawa.Serialisation.GeneratorTest do
  use ThamaniDawa.DataCase, async: true

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Gs1Api
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Serialisation
  alias ThamaniDawa.Serialisation.SerialisedCode
  alias ThamaniDawa.Serialisation.SerialisedRequest
  alias ThamaniDawa.Serialisation.Shipment
  alias ThamaniDawa.Serialisation.Sscc
  alias ThamaniDawa.Serialisation.SsccRequest

  @gtin "06164005056791"

  setup do
    organization = organization_fixture(%{kind: :distributor})
    user = user_fixture(%{organization_id: organization.id})
    {:ok, scope: Scope.for_user(user)}
  end

  defp sscc_request(attrs \\ %{}) do
    %SsccRequest{}
    |> SsccRequest.changeset(
      Map.merge(
        %{
          "gtin" => @gtin,
          "batch" => "HC-2608-A",
          "production_date" => "2026-08-03",
          "expiry_date" => "2028-08-03",
          "count_of_trade_items" => "8",
          "material_description" => "Temperature-controlled healthcare products",
          "order_number" => "PO-10362-001",
          "from_address" => "Nairobi, Kenya",
          "to_address" => "Enterprise Road, Nairobi"
        },
        attrs
      )
    )
    |> Ecto.Changeset.apply_action!(:insert)
  end

  defp serialised_request(attrs \\ %{}) do
    %SerialisedRequest{}
    |> SerialisedRequest.changeset(
      Map.merge(
        %{
          "gtin" => @gtin,
          "batch" => "HC-2608-B",
          "production_date" => "2026-08-10",
          "expiry_date" => "2028-08-10",
          "trade_item_qty" => "8",
          "shipper_qty" => "4"
        },
        attrs
      )
    )
    |> Ecto.Changeset.apply_action!(:insert)
  end

  describe "generate_sscc/2" do
    test "records the SSCC GS1 issued", %{scope: scope} do
      Req.Test.stub(Gs1Api, fn conn ->
        Req.Test.json(conn, %{"sscc" => %{"sscc" => "161640050000010001"}})
      end)

      assert {:ok, shipment, sscc} = Serialisation.generate_sscc(scope, sscc_request())

      assert shipment.status == :issued
      assert shipment.type == :sscc
      assert sscc.code == "161640050000010001"
      assert sscc.level == :pallet
      assert [item] = sscc.items
      assert item.gtin == @gtin
      assert item.count == 8
    end

    test "a rejection leaves a failed shipment and no codes", %{scope: scope} do
      Req.Test.stub(Gs1Api, fn conn ->
        conn
        |> Plug.Conn.put_status(422)
        |> Req.Test.json(%{"result" => "No GS1 company prefix on this account"})
      end)

      assert {:error, error} = Serialisation.generate_sscc(scope, sscc_request())
      assert error.message == "No GS1 company prefix on this account"

      assert [%Shipment{status: :failed}] = Repo.all(Shipment)
      assert Repo.all(Sscc) == []
    end

    test "a 2xx with no code is a failure, not a locally minted one", %{scope: scope} do
      Req.Test.stub(Gs1Api, fn conn -> Req.Test.json(conn, %{"result" => "queued"}) end)

      assert {:error, error} = Serialisation.generate_sscc(scope, sscc_request())
      assert error.reason == :unexpected_response
      assert Repo.all(Sscc) == []
    end
  end

  describe "generate_serialised/2" do
    test "records the pallet, its shippers, and every primary serial", %{scope: scope} do
      Req.Test.stub(Gs1Api, fn conn ->
        Req.Test.json(conn, %{
          "sscc" => "161640050000010018",
          "shippers" => [
            %{
              "sscc" => "261640050000010110",
              "serial" => "SHIP103621001",
              "primary_serials" => ["HC10362200001", "HC10362200002"]
            },
            %{
              "sscc" => "261640050000010120",
              "serial" => "SHIP103621002",
              "primary_serials" => ["HC10362200003", "HC10362200004"]
            }
          ]
        })
      end)

      assert {:ok, shipment, pallet} =
               Serialisation.generate_serialised(
                 scope,
                 serialised_request(%{"trade_item_qty" => "4", "shipper_qty" => "2"})
               )

      assert shipment.status == :issued
      assert pallet.code == "161640050000010018"

      group = Serialisation.get_group!(scope.organization_id, pallet.id)
      assert Serialisation.group_totals(group) == %{shippers: 2, primaries: 4}

      assert Repo.all(SerialisedCode) |> Enum.map(& &1.serial) |> Enum.sort() == [
               "HC10362200001",
               "HC10362200002",
               "HC10362200003",
               "HC10362200004"
             ]
    end

    test "a flat serial list is stored as one implicit shipper", %{scope: scope} do
      Req.Test.stub(Gs1Api, fn conn ->
        Req.Test.json(conn, %{
          "sscc" => "161640050000010025",
          "primary_serials" => ["HC10362200009"]
        })
      end)

      assert {:ok, _shipment, pallet} =
               Serialisation.generate_serialised(
                 scope,
                 serialised_request(%{"trade_item_qty" => "1", "shipper_qty" => "1"})
               )

      group = Serialisation.get_group!(scope.organization_id, pallet.id)
      assert Serialisation.group_totals(group).primaries == 1
    end
  end

  describe "SerialisedRequest" do
    test "reports the serials GS1 will authorize: trade items plus shippers" do
      request = serialised_request(%{"trade_item_qty" => "1000", "shipper_qty" => "20"})

      assert SerialisedRequest.shipper_count(request) == 50
      assert SerialisedRequest.authorized_serials(request) == 1050
    end

    test "rejects a shipper larger than the run" do
      changeset =
        SerialisedRequest.changeset(%SerialisedRequest{}, %{
          "gtin" => @gtin,
          "batch" => "B",
          "production_date" => "2026-08-10",
          "expiry_date" => "2028-08-10",
          "trade_item_qty" => "4",
          "shipper_qty" => "8"
        })

      assert %{shipper_qty: ["cannot be more than the total number of trade items"]} =
               errors_on(changeset)
    end

    test "rejects an expiry before production" do
      changeset =
        SerialisedRequest.changeset(%SerialisedRequest{}, %{
          "gtin" => @gtin,
          "batch" => "B",
          "production_date" => "2026-08-10",
          "expiry_date" => "2025-08-10",
          "trade_item_qty" => "4",
          "shipper_qty" => "2"
        })

      assert %{expiry_date: ["must be on or after the production date"]} = errors_on(changeset)
    end
  end
end
