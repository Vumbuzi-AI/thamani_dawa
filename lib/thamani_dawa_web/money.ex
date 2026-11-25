defmodule ThamaniDawaWeb.Money do
  @moduledoc "Shared money text for the UI: `KSh 1,450`."

  def ksh(nil), do: ksh(Decimal.new(0))
  def ksh(amount) when is_integer(amount), do: ksh(Decimal.new(amount))
  def ksh(amount) when is_float(amount), do: ksh(Decimal.from_float(amount))

  def ksh(amount) when is_binary(amount) do
    case Decimal.parse(String.replace(amount, ",", "")) do
      {%Decimal{} = decimal, _rest} -> ksh(decimal)
      _ -> ksh(Decimal.new(0))
    end
  end

  def ksh(%Decimal{} = amount) do
    "KSh " <> group(amount |> Decimal.round(0) |> Decimal.to_integer())
  end

  @doc "Axis labels: `KSh 80k`, `KSh 1.2M`, or `KSh 0`."
  def compact(amount) do
    n = to_int(amount)
    abs_n = abs(n)

    label =
      cond do
        abs_n >= 1_000_000 -> "#{trim_compact(n / 1_000_000)}M"
        abs_n >= 1_000 -> "#{trim_compact(n / 1_000)}k"
        true -> group(n)
      end

    "KSh " <> label
  end

  defp to_int(nil), do: 0
  defp to_int(%Decimal{} = amount), do: amount |> Decimal.round(0) |> Decimal.to_integer()
  defp to_int(n) when is_integer(n), do: n
  defp to_int(n) when is_float(n), do: round(n)
  defp to_int(other), do: other |> ksh() |> String.replace(~r/[^0-9-]/, "") |> String.to_integer()

  defp trim_compact(n) do
    n
    |> Float.round(1)
    |> :erlang.float_to_binary(decimals: 1)
    |> String.replace_suffix(".0", "")
  end

  def group(int) when int < 0, do: "-" <> group(-int)

  def group(int) do
    int
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end
end
