defmodule ThamaniDawa.KmlttbTest do
  use ExUnit.Case, async: true

  alias ThamaniDawa.Kmlttb

  describe "search_facilities/1" do
    test "returns matching facilities" do
      assert {:ok, [facility]} = Kmlttb.search_facilities("Unique Lab")
      assert facility.name == "UNIQUE LAB LTD"
      assert facility.id == "1"
    end

    test "returns an empty list when nothing matches" do
      assert {:ok, []} = Kmlttb.search_facilities("Nonexistent Lab")
    end
  end

  describe "fetch_detail/1" do
    test "parses the licence number and other fields" do
      assert {:ok, detail} = Kmlttb.fetch_detail("1")
      assert detail.license_no == "L 01000/26"
      assert detail.county == "NAIROBI"
      assert detail.status == "ACTIVE"
    end
  end

  describe "license_match?/2" do
    test "matches exact values, ignoring whitespace and case" do
      assert Kmlttb.license_match?("l01000/26", "L 01000/26")
      refute Kmlttb.license_match?("L 09999/26", "L 01000/26")
    end
  end

  describe "verify_license/2" do
    test "returns :verified for a unique match" do
      assert {:ok, :verified, detail} = Kmlttb.verify_license("Unique Lab", "L 01000/26")
      assert detail.name == "UNIQUE LAB LTD"
    end

    test "returns :ambiguous when multiple candidates share a license number" do
      assert {:ok, :ambiguous, details} = Kmlttb.verify_license("Ambiguous Lab", "L 02000/26")
      assert length(details) == 2
    end

    test "returns :name_not_found when the search has no candidates" do
      assert {:error, :name_not_found} = Kmlttb.verify_license("Nonexistent Lab", "L 01000/26")
    end

    test "returns :license_mismatch when candidates exist but none match the license" do
      assert {:error, :license_mismatch} = Kmlttb.verify_license("Unique Lab", "L 99999/26")
    end

    test "returns :license_inactive when the match's status isn't ACTIVE" do
      assert {:ok, :license_inactive, detail} =
               Kmlttb.verify_license("Inactive Lab", "L 03000/26")

      assert detail.status == "SUSPENDED"
    end
  end
end
