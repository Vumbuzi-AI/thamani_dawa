defmodule ThamaniDawa.GS1EncoderTest do
  use ExUnit.Case, async: true

  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.GS1Decoder
  alias ThamaniDawa.GS1Encoder

  @gs <<29>>

  describe "encode_raw/1" do
    test "encodes full batch details into standard GS1 element string and decodes via GS1Decoder" do
      batch = %Batch{
        gtin: "00614141000012",
        batch_no: "LOT123A",
        manufacture_date: ~D[2024-01-15],
        expiry_date: ~D[2026-02-28],
        serial: "SN0001"
      }

      encoded = GS1Encoder.encode_raw(batch)

      expected =
        "01" <>
          "00614141000012" <>
          "10" <>
          "LOT123A" <> @gs <> "11" <> "240115" <> "17" <> "260228" <> "21" <> "SN0001"

      assert encoded == expected

      assert {:ok, decoded} = GS1Decoder.parse(encoded)

      assert decoded.gtin == "00614141000012"
      assert decoded.batch_no == "LOT123A"
      assert decoded.production_date == ~D[2024-01-15]
      assert decoded.expiry_date == ~D[2026-02-28]
      assert decoded.serial == "SN0001"
    end

    test "omits AI 21 when serial is nil or empty" do
      batch = %Batch{
        gtin: "00614141000012",
        batch_no: "LOT999",
        manufacture_date: ~D[2025-05-10],
        expiry_date: ~D[2027-12-31],
        serial: nil
      }

      encoded = GS1Encoder.encode_raw(batch)

      expected =
        "01" <>
          "00614141000012" <> "10" <> "LOT999" <> @gs <> "11" <> "250510" <> "17" <> "271231"

      assert encoded == expected
      assert {:ok, decoded} = GS1Decoder.parse(encoded)
      assert decoded.serial == nil
    end

    test "omits AI 11 when manufacture_date is nil" do
      batch = %Batch{
        gtin: "00614141000012",
        batch_no: "LOT888",
        manufacture_date: nil,
        expiry_date: ~D[2028-06-30],
        serial: "SN-999"
      }

      encoded = GS1Encoder.encode_raw(batch)

      expected =
        "01" <>
          "00614141000012" <> "10" <> "LOT888" <> @gs <> "17" <> "280630" <> "21" <> "SN-999"

      assert encoded == expected
      assert {:ok, decoded} = GS1Decoder.parse(encoded)
      assert decoded.production_date == nil
      assert decoded.expiry_date == ~D[2028-06-30]
    end
  end

  describe "human_readable/1" do
    test "formats parenthesized GS1 element string" do
      batch = %Batch{
        gtin: "00614141000012",
        batch_no: "LOT123A",
        manufacture_date: ~D[2024-01-15],
        expiry_date: ~D[2026-02-28],
        serial: "SN0001"
      }

      assert GS1Encoder.human_readable(batch) ==
               "(01)00614141000012(10)LOT123A(11)240115(17)260228(21)SN0001"
    end
  end
end
