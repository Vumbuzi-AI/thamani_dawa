defmodule ThamaniDawa.ApiIdempotencyTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.ApiIdempotency

  import ThamaniDawa.AccountsFixtures

  test "replays a stored success and rejects a different body" do
    user = user_fixture()
    params = %{"amount" => "10"}

    assert {:ok, 201, %{"data" => "ok"}} =
             ApiIdempotency.execute(user.id, "sale-1", params, fn -> {:ok, 201, %{data: "ok"}} end)

    assert {:ok, 201, %{"data" => "ok"}} =
             ApiIdempotency.execute(user.id, "sale-1", params, fn ->
               {:ok, 201, %{data: "other"}}
             end)

    assert {:error, :idempotency_conflict} =
             ApiIdempotency.execute(user.id, "sale-1", %{"amount" => "11"}, fn ->
               {:ok, 201, %{data: "nope"}}
             end)
  end

  test "a failed attempt is not stored" do
    user = user_fixture()
    params = %{"amount" => "10"}

    assert {:error, :out_of_stock} =
             ApiIdempotency.execute(user.id, "sale-2", params, fn -> {:error, :out_of_stock} end)

    assert {:ok, 201, %{"data" => "ok"}} =
             ApiIdempotency.execute(user.id, "sale-2", params, fn -> {:ok, 201, %{data: "ok"}} end)
  end
end
