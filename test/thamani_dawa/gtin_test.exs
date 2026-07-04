defmodule ThamaniDawa.GtinTest do
  use ExUnit.Case, async: true

  alias ThamaniDawa.Gtin

  defp changeset(params) do
    Ecto.Changeset.cast({%{}, %{gtin: :string}}, params, [:gtin])
  end

  describe "validate_gtin/2" do
    test "is a no-op when the field wasn't changed" do
      changeset = changeset(%{}) |> Gtin.validate_gtin()
      assert changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :gtin)
    end

    test "normalizes a shorter GTIN to canonical GTIN-14" do
      changeset = changeset(%{gtin: "614141000012"}) |> Gtin.validate_gtin()
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :gtin) == "00614141000012"
    end

    test "rejects a code with an invalid check digit" do
      changeset = changeset(%{gtin: "00614141000011"}) |> Gtin.validate_gtin()
      refute changeset.valid?
      assert {"is not a valid GTIN", []} = changeset.errors[:gtin]
    end
  end

  describe "generate/1" do
    test "appends a valid GS1 check digit to a 13-digit base code" do
      assert {:ok, gtin} = Gtin.generate("0000000000001")
      assert {:ok, "GTIN-14"} = ExGtin.validate(gtin)
    end
  end
end
