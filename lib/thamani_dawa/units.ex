defmodule ThamaniDawa.Units do
  @moduledoc """
  Human-readable labels for the unit-of-measure codes we store on `Product.uom`.

  Products keep the UN/ECE (GS1) code — `"H87"`, `"U2"`, `"KGM"` — because that
  is what the GS1 registry and EPCIS payloads expect. Those codes are opaque to
  the people using the app, so every UI surface renders them through this
  module instead of printing the raw code.

  Values that are not codes (free-text units typed during a CSV import, e.g.
  `"tablet"`) are passed through as-is, so imports keep working.
  """

  @labels %{
    "H87" => "piece",
    "C62" => "unit",
    "U2" => "tablet",
    "AV" => "capsule",
    "PK" => "pack",
    "PA" => "packet",
    "DZN" => "dozen",
    "PR" => "pair",
    "RO" => "roll",
    "ZP" => "page",
    "KGM" => "kilogram",
    "GRM" => "gram",
    "MGM" => "milligram",
    "LTR" => "litre",
    "MLT" => "millilitre",
    "CTL" => "centilitre",
    "MTR" => "metre",
    "CMT" => "centimetre",
    "MMT" => "millimetre",
    "INH" => "inch",
    "AMP" => "ampere",
    "KWT" => "kilowatt",
    "WTT" => "watt",
    "VLT" => "volt",
    "KVT" => "kilovolt",
    "LTN" => "ton",
    "ONZ" => "ounce"
  }

  @order [
    "H87",
    "C62",
    "U2",
    "AV",
    "PK",
    "PA",
    "DZN",
    "PR",
    "RO",
    "ZP",
    "KGM",
    "GRM",
    "MGM",
    "LTR",
    "MLT",
    "CTL",
    "MTR",
    "CMT",
    "MMT",
    "INH",
    "AMP",
    "KWT",
    "WTT",
    "VLT",
    "KVT",
    "LTN",
    "ONZ"
  ]

  @doc """
  The unit-of-measure options offered in product forms, as `{label, code}`
  pairs. The code is kept visible so users can match units against GS1 data
  and the CSV import template.
  """
  @spec options() :: [{String.t(), String.t()}]
  def options do
    Enum.map(@order, fn code -> {"#{String.capitalize(@labels[code])} (#{code})", code} end)
  end

  @doc """
  The friendly singular label for a stored unit, e.g. `"H87"` -> `"piece"`.

  Codes we don't know fall back to the generic `"unit"`; free-text values are
  returned as they were typed.
  """
  @spec label(String.t() | nil) :: String.t() | nil
  def label(nil), do: nil

  def label(uom) when is_binary(uom) do
    trimmed = String.trim(uom)

    cond do
      trimmed == "" -> nil
      code?(trimmed) -> Map.get(@labels, trimmed, "unit")
      true -> trimmed
    end
  end

  @doc """
  The friendly label for a stored unit, pluralized against `count`.

  `"H87"` with a count of 10 gives `"pieces"`; with a count of 1, `"piece"`.
  """
  @spec label(String.t() | nil, non_neg_integer) :: String.t()
  def label(uom, count) when is_integer(count) and count >= 0 do
    case label(uom) do
      nil -> if(count == 1, do: "unit", else: "units")
      base -> if(count == 1, do: base, else: pluralize(base))
    end
  end

  @doc """
  A quantity with its unit, e.g. `10` pieces of `"H87"` -> `"10 pieces"`.
  """
  @spec format(non_neg_integer, String.t() | nil) :: String.t()
  def format(count, uom) when is_integer(count) and count >= 0,
    do: "#{count} #{label(uom, count)}"

  defp code?(value), do: Regex.match?(~r/^[A-Z0-9]{2,3}$/, value)

  defp pluralize("dozen"), do: "dozen"
  defp pluralize("inch"), do: "inches"

  defp pluralize(word) do
    cond do
      String.ends_with?(word, ["s", "x", "z", "ch", "sh"]) -> word <> "es"
      String.match?(word, ~r/[^aeiou]y$/i) -> String.slice(word, 0..-2//1) <> "ies"
      true -> word <> "s"
    end
  end
end
