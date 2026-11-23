defmodule ThamaniDawa.GS1.Sscc do
  @moduledoc """
  SSCC-18 check digits.

  Case SSCCs are minted by `ThamaniDawa.GS1.MemberApi` (`create_sscc`). This
  module only checks digits on identifiers the platform stores or scans.
  """

  @doc """
  Computes the GS1 Mod-10 check digit for a numeric string.

  Weights alternate 3, 1, 3, 1, … from the rightmost digit of `digits`.
  """
  @spec mod10_check_digit(String.t()) :: non_neg_integer()
  def mod10_check_digit(digits) when is_binary(digits) do
    sum =
      digits
      |> String.reverse()
      |> String.graphemes()
      |> Enum.with_index()
      |> Enum.reduce(0, fn {digit, index}, acc ->
        weight = if rem(index, 2) == 0, do: 3, else: 1
        acc + String.to_integer(digit) * weight
      end)

    rem(10 - rem(sum, 10), 10)
  end
end
