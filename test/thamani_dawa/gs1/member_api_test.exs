defmodule ThamaniDawa.GS1.MemberApiTest do
  use ExUnit.Case, async: true

  alias ThamaniDawa.GS1.MemberApi

  test "reads the minted SSCC from the member API body" do
    body = %{"sscc" => %{"result" => "success", "sscc" => "061600000000000019"}}

    assert {:ok, "061600000000000019"} = MemberApi.decode_create_response({:ok, 200, body})
  end

  test "classifies member API errors" do
    assert {:error, :not_found} =
             MemberApi.decode_contents_response({:ok, 404, %{"result" => "code does not exist!"}})

    assert {:error, :unavailable} = MemberApi.decode_contents_response({:error, :timeout})
    assert {:error, :unconfigured} = MemberApi.decode_create_response({:error, :unconfigured})

    assert {:error, {:invalid, "Missing required parameters. Please provide batch_info."}} =
             MemberApi.decode_create_response(
               {:ok, 400,
                %{"result" => "Missing required parameters. Please provide batch_info."}}
             )

    assert {:ok, %{"sscc" => "061600000000000019", "products" => []}} =
             MemberApi.decode_contents_response(
               {:ok, 200, %{"sscc" => "061600000000000019", "products" => []}}
             )
  end
end
