defmodule ThamaniDawa.GrpTest do
  use ExUnit.Case, async: true

  alias ThamaniDawa.Grp

  describe "verify_prefix/1" do
    test "returns :verified for a prefix with an active licence" do
      assert {:ok, :verified, licence} = Grp.verify_prefix("0614141")
      assert licence["licenceStatus"] == "ACTIVE"
    end

    test "returns :inactive for a prefix whose licence is no longer active" do
      assert {:ok, :inactive, licence} = Grp.verify_prefix("9996141")
      assert licence["licenceStatus"] == "WITHDRAWN"
    end

    test "returns :not_verified for a prefix the registry doesn't know" do
      assert {:ok, :not_verified} = Grp.verify_prefix("0000000")
    end
  end

  describe "verify_gln/1" do
    test "returns :verified for a GLN with an active licence" do
      assert {:ok, :verified, licence} = Grp.verify_gln("0614141000784")
      assert licence["licenceStatus"] == "ACTIVE"
    end

    test "returns :inactive for a GLN whose licence is no longer active" do
      assert {:ok, :inactive, licence} = Grp.verify_gln("9996141000454")
      assert licence["licenceStatus"] == "WITHDRAWN"
    end

    test "returns :not_verified for a GLN the registry doesn't know" do
      assert {:ok, :not_verified} = Grp.verify_gln("0000000000000")
    end
  end
end
