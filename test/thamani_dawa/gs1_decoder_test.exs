defmodule ThamaniDawa.GS1DecoderTest do
  use ExUnit.Case, async: true

  alias ThamaniDawa.GS1Decoder

  @gs <<29>>

  describe "parse/1" do
    test "decodes GTIN, dates, batch/lot and serial from a full element string" do
      data =
        "01" <>
          "00614141000012" <>
          "11" <> "240115" <> "17" <> "260228" <> "10" <> "LOT123A" <> @gs <> "21" <> "SN0001"

      assert {:ok, result} = GS1Decoder.parse(data)

      assert result == %{
               gtin: "00614141000012",
               batch_no: "LOT123A",
               production_date: ~D[2024-01-15],
               expiry_date: ~D[2026-02-28],
               serial: "SN0001",
               gln: nil
             }
    end

    test "decodes a GLN from AI 414" do
      assert {:ok, result} = GS1Decoder.parse("414" <> "0614141000005")
      assert result.gln == "0614141000005"
      assert result.gtin == nil
    end

    test "parses a GLN (AI 414) followed by another fixed-length AI" do
      data = "414" <> "0614141000005" <> "01" <> "00614141000012"

      assert {:ok, result} = GS1Decoder.parse(data)
      assert result.gln == "0614141000005"
      assert result.gtin == "00614141000012"
    end

    test "a variable-length field mid-string is terminated by the GS separator" do
      data = "10" <> "ABC" <> @gs <> "01" <> "00614141000012"
      assert {:ok, result} = GS1Decoder.parse(data)
      assert result.batch_no == "ABC"
      assert result.gtin == "00614141000012"
    end

    test "a variable-length field runs to the end of the string when it's last" do
      assert {:ok, result} = GS1Decoder.parse("21" <> "SERIAL-XYZ")
      assert result.serial == "SERIAL-XYZ"
    end

    test "strips a leading FNC1/group-separator byte" do
      assert {:ok, result} = GS1Decoder.parse(@gs <> "01" <> "00614141000012")
      assert result.gtin == "00614141000012"
    end

    test "day 00 means the last day of the month" do
      assert {:ok, result} = GS1Decoder.parse("17" <> "260200")
      assert result.expiry_date == ~D[2026-02-28]
    end

    test "applies the GS1 century pivot to two-digit years" do
      assert {:ok, %{production_date: ~D[2026-01-01]}} = GS1Decoder.parse("11" <> "260101")
      assert {:ok, %{production_date: ~D[2049-01-01]}} = GS1Decoder.parse("11" <> "490101")
      assert {:ok, %{production_date: ~D[1950-01-01]}} = GS1Decoder.parse("11" <> "500101")
      assert {:ok, %{production_date: ~D[1999-01-01]}} = GS1Decoder.parse("11" <> "990101")
    end

    test "errors on an AI this system doesn't handle" do
      assert {:error, {:unrecognized_ai, _rest}} = GS1Decoder.parse("99" <> "ABC")
    end

    test "errors when a fixed-length AI is truncated" do
      assert {:error, {:invalid_length, "01"}} = GS1Decoder.parse("01" <> "123")
    end

    test "errors on an invalid date" do
      assert {:error, {:invalid_date, _}} = GS1Decoder.parse("17" <> "261340")
    end

    test "errors on invalid day-00 date components" do
      assert {:error, {:invalid_date, _}} = GS1Decoder.parse("17" <> "261300")
    end

    test "errors when the GTIN isn't numeric" do
      assert {:error, {:invalid_digits, _}} = GS1Decoder.parse("01" <> "0061414100001A")
    end

    test "errors when a GLN (AI 414) is truncated" do
      assert {:error, {:invalid_length, "414"}} = GS1Decoder.parse("414" <> "123")
    end

    test "errors when a GLN isn't numeric" do
      assert {:error, {:invalid_digits, _}} = GS1Decoder.parse("414" <> "061414100000A")
    end

    test "GLN parse returns an error for invalid input (length or digits)" do
      result = GS1Decoder.parse("414" <> "06141A")

      case result do
        {:error, {:invalid_length, "414"}} -> assert true
        {:error, {:invalid_digits, _}} -> assert true
        other -> flunk("Unexpected parse result: #{inspect(other)}")
      end
    end

    test "empty input returns the expected GS1 keys with nil values" do
      assert {:ok, result} = GS1Decoder.parse("")

      assert result == %{
               gtin: nil,
               batch_no: nil,
               production_date: nil,
               expiry_date: nil,
               serial: nil,
               gln: nil
             }

      assert MapSet.new(Map.keys(result)) ==
               MapSet.new([
                 :gtin,
                 :batch_no,
                 :production_date,
                 :expiry_date,
                 :serial,
                 :gln
               ])
    end

    test "an AI present but with no value decodes to an empty string, not an error" do
      assert {:ok, result} = GS1Decoder.parse("10")
      assert result.batch_no == ""
    end

    test "an empty variable-length AI is empty when terminated by a GS separator" do
      assert {:ok, result} = GS1Decoder.parse("10" <> @gs)
      assert result.batch_no == ""
    end

    test "fixed-length AI with no value returns invalid_length" do
      assert {:error, {:invalid_length, "01"}} = GS1Decoder.parse("01")
    end

    test "when an AI appears twice, the later occurrence wins" do
      data = "01" <> "00614141000012" <> "01" <> "00614141000029"
      assert {:ok, result} = GS1Decoder.parse(data)
      assert result.gtin == "00614141000029"
    end

    test "duplicate variable-length AI entries overwrite earlier values" do
      data = "10" <> "FIRST" <> @gs <> "10" <> "SECOND"
      assert {:ok, result} = GS1Decoder.parse(data)
      assert result.batch_no == "SECOND"
    end
  end
end
