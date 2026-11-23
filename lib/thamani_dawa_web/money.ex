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
