defmodule ThamaniDawa.Serialisation.LabelTest do
  use ExUnit.Case, async: true

  alias ThamaniDawa.Serialisation.Label
  alias ThamaniDawa.Serialisation.SerialisedCode
  alias ThamaniDawa.Serialisation.Shipment
  alias ThamaniDawa.Serialisation.Sscc
  alias ThamaniDawa.Serialisation.SsccItem

  defp shipment do
    %Shipment{
      batch: "HC-2608-A",
      production_date: ~D[2026-08-03],
      expiry_date: ~D[2028-08-03],
      order_number: "PO-10362-001",
      material_description: "Temperature-controlled healthcare products",
      from_company_name: "Test GS1 company Ltd",
      from_address: "Nairobi, Kenya",
      to_company_name: "Central Medical Stores",
      to_address: "Enterprise Road, Nairobi"
    }
  end

  defp pallet do
    %Sscc{
      code: "161640050000010001",
      level: :pallet,
      items: [%SsccItem{gtin: "06164005056791", count: 8, items: 8}]
    }
  end

  describe "pallet/3" do
    test "carries the AIs the artwork prints, in order" do
      label = Label.pallet(pallet(), shipment(), sequence: {1, 1})

      assert Label.ai_lines(label) == [
               "(00) 161640050000010001",
               "(01) 06164005056791",
               "(10) HC-2608-A",
               "(17) 280803",
               "(11) 260803",
               "(37) 8",
               "(400) PO-10362-001"
             ]
    end

    test "the Data Matrix payload matches the printed AI lines" do
      label = Label.pallet(pallet(), shipment())

      encoded = Label.gs1_text(label)

      for line <- Label.ai_lines(label) do
        assert encoded =~ String.replace(line, ") ", ")")
      end
    end

    test "an absent AI is dropped rather than printed empty" do
      label = Label.pallet(pallet(), %{shipment() | order_number: nil, expiry_date: nil})

      refute Label.gs1_text(label) =~ "(400)"
      refute Label.gs1_text(label) =~ "(17)"
    end

    test "takes the quantity from the item matching the GTIN being viewed" do
      mixed = %Sscc{
        pallet()
        | items: [
            %SsccItem{gtin: "06164005056791", count: 8, items: 8},
            %SsccItem{gtin: "06164005056807", count: 3, items: 3}
          ]
      }

      label = Label.pallet(mixed, shipment(), gtin: "06164005056807")

      assert label.quantity == 3
      assert Label.gs1_text(label) =~ "(01)06164005056807(10)"
    end
  end

  describe "shipper/3" do
    test "adds the shipper serial under AI (21)" do
      shipper = %Sscc{
        code: "261640050000010110",
        level: :case,
        items: [%SsccItem{gtin: "06164005056791", count: 4, items: 4}]
      }

      label = Label.shipper(shipper, shipment(), serial: "SHIP103621001")

      assert List.last(Label.ai_lines(label)) == "(21) SHIP103621001"
      assert label.quantity == 4
    end
  end

  describe "primary/2" do
    test "prints only the trade item AIs" do
      code = %SerialisedCode{gtin: "06164005056791", serial: "HC10362200001"}

      label = Label.primary(code, %{shipment() | batch: "HC-2608-B"})

      assert Label.ai_lines(label) == [
               "(01) 06164005056791",
               "(10) HC-2608-B",
               "(17) 280803",
               "(11) 260803",
               "(21) HC10362200001"
             ]
    end
  end

  describe "filename/1" do
    test "identifies the artifact and survives punctuation in a batch" do
      code = %SerialisedCode{gtin: "06164005056791", serial: "HC10362200001"}

      assert Label.filename(Label.primary(code, %{shipment() | batch: "HC/2608 A"})) ==
               "primary-06164005056791-HC-2608-A-HC10362200001"
    end
  end

  describe "ai_date/1" do
    test "renders YYMMDD, keeping leading zeroes" do
      assert Label.ai_date(~D[2026-01-05]) == "260105"
      assert Label.ai_date(nil) == nil
    end
  end
end
