defmodule ThamaniDawa.PpbTest do
  use ExUnit.Case, async: true

  alias ThamaniDawa.Ppb

  describe "search_facilities/2" do
    test "returns matching facilities" do
      assert {:ok, [facility]} = Ppb.search_facilities("Unique Pharmacy")
      assert facility.name == "UNIQUE PHARMACY LTD"
      assert facility.id == "1"
    end

    test "returns an empty list when nothing matches" do
      assert {:ok, []} = Ppb.search_facilities("Nonexistent Facility")
    end
  end

  describe "fetch_detail/1" do
    test "parses the masked license and other fields" do
      assert {:ok, detail} = Ppb.fetch_detail("1")
      assert detail.masked_license == "AB1****9999"
      assert detail.county == "Nairobi"
      assert detail.status == "VALID"
      assert detail.valid_till == "2026-12-31"
    end
  end

  describe "license_match?/2" do
    test "matches same-length entries with matching prefix/suffix" do
      assert Ppb.license_match?("AB1XXXX9999", "AB1****9999")
      refute Ppb.license_match?("ZZ1XXXX9999", "AB1****9999")
      refute Ppb.license_match?("AB1XXX9999", "AB1****9999")
    end

    test "is case-insensitive and ignores whitespace" do
      assert Ppb.license_match?("ab1 xxxx 9999", "AB1****9999")
    end
  end

  describe "verify_license/3" do
    test "returns :verified for a unique match" do
      assert {:ok, :verified, detail} = Ppb.verify_license("Unique Pharmacy", "AB1XXXX9999")
      assert detail.name == "UNIQUE PHARMACY LTD"
    end

    test "returns :ambiguous when multiple candidates share a mask" do
      assert {:ok, :ambiguous, details} =
               Ppb.verify_license("Ambiguous Pharmacy", "CD2XXXX1111")

      assert length(details) == 2
    end

    test "returns :name_not_found when the search has no candidates" do
      assert {:error, :name_not_found} = Ppb.verify_license("Nonexistent Facility", "AB1XXXX9999")
    end

    test "returns :license_mismatch when candidates exist but none match the license" do
      assert {:error, :license_mismatch} = Ppb.verify_license("Unique Pharmacy", "ZZ9XXXX0000")
    end

    test "returns :license_inactive when the match's licence status isn't VALID" do
      assert {:ok, :license_inactive, detail} =
               Ppb.verify_license("Inactive Pharmacy", "GH4XXXX3333")

      assert detail.status == "SUSPENDED"
    end
  end
end
