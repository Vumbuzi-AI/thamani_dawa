defmodule ThamaniDawa.PbbNumberTest do
  use ExUnit.Case, async: true
  alias ThamaniDawa.PbbNumber

  describe "normalize/1" do
    test "strips spaces and converts to uppercase" do
      assert PbbNumber.normalize(" ppb/prm/1234 ") == "PPB/PRM/1234"
      assert PbbNumber.normalize("p/ 9876") == "P/9876"
    end

    test "handles nil and empty strings gracefully" do
      assert PbbNumber.normalize(nil) == ""
      assert PbbNumber.normalize("") == ""
    end
  end

  describe "validate_format/1" do
    test "validates valid PPB premise format" do
      assert {:ok, "PPB/PRM/1234"} = PbbNumber.validate_format("ppb/prm/1234")
      assert {:ok, "PPB/PREM/5678"} = PbbNumber.validate_format("PPB/PREM/5678")
    end

    test "validates practitioner licenses" do
      assert {:ok, "P/1234"} = PbbNumber.validate_format("p/1234")
      assert {:ok, "PT/5678"} = PbbNumber.validate_format("pt/5678")
    end

    test "validates numeric license numbers" do
      assert {:ok, "123456"} = PbbNumber.validate_format("123456")
    end

    test "rejects invalid formats" do
      assert {:error, :invalid_format} = PbbNumber.validate_format("INVALID@123")
      assert {:error, :invalid_format} = PbbNumber.validate_format("AB")
      assert {:error, :invalid_format} = PbbNumber.validate_format(nil)
    end
  end
end
