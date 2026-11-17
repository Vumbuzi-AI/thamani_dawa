defmodule ThamaniDawa.Epcis.UrnTest do
  use ExUnit.Case, async: true

  alias ThamaniDawa.Epcis.Urn

  doctest ThamaniDawa.Epcis.Urn

  test "sgtin rejects non-numeric and wrong-length input" do
    assert {:error, :not_numeric} = Urn.sgtin("0061414110734X", "1", 7)
    assert {:error, :invalid_length} = Urn.sgtin("0614141107346", "1", 7)
  end

  test "sgtin rejects serials outside the GS1 AI(21) charset" do
    assert {:error, :invalid_serial} = Urn.sgtin("00614141107346", "BAD#SERIAL", 7)
    assert {:error, :invalid_serial} = Urn.sgtin("00614141107346", String.duplicate("1", 21), 7)
  end

  test "prefix_length_for skips the indicator digit on GTIN-14s" do
    assert Urn.prefix_length_for("00614141107346", "0614141") == 7
  end

  test "prefix_length_for skips the extension digit on SSCC-18s" do
    assert Urn.prefix_length_for("006141411234567890", "0614141") == 7
  end

  test "prefix_length_for falls back to the default for foreign identifiers" do
    assert Urn.prefix_length_for("6164000000224", "0614141") == Urn.default_prefix_length()
  end

  test "invalid prefix lengths are rejected" do
    assert {:error, :invalid_prefix_length} = Urn.sgln("0614141000012", 12)
    assert {:error, :invalid_prefix_length} = Urn.sgtin("00614141107346", "1", 13)
  end
end
