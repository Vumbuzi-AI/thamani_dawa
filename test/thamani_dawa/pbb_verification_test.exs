defmodule ThamaniDawa.PbbVerificationTest do
  use ExUnit.Case, async: true
  alias ThamaniDawa.PbbVerification

  setup do
    Application.put_env(:thamani_dawa, :pbb_verification_backend, :mock)
    on_exit(fn -> Application.delete_env(:thamani_dawa, :pbb_verification_backend) end)
    :ok
  end

  describe "verify/1 in mock mode" do
    test "returns verified status for standard valid formats" do
      assert {:ok, %{status: :verified, premise_name: "Mock Pharmacy Ltd"}} =
               PbbVerification.verify("PPB/PRM/1234")
    end

    test "returns invalid_license when license contains INVALID" do
      assert {:ok, %{status: :invalid_license}} = PbbVerification.verify("PPB/PRM/INVALID123")
    end

    test "returns timeout error when license contains TIMEOUT" do
      assert {:error, :timeout} = PbbVerification.verify("PPB/PRM/TIMEOUT123")
    end

    test "returns invalid_format error for malformed string" do
      assert {:error, :invalid_format} = PbbVerification.verify("ABC")
    end
  end
end
