defmodule ThamaniDawa.GS1Decoder do
  @moduledoc """
  Decodes a GS1 element string — the payload of a scanned GS1 DataMatrix or
  GS1-128 barcode — into the Application Identifiers this system acts on
  (§3 of project.md):

    * `01`  GTIN (fixed, 14 digits)
    * `10`  Batch/lot number (variable, up to 20 characters)
    * `11`  Production date, `YYMMDD` (fixed, 6 digits)
    * `17`  Expiry date, `YYMMDD` (fixed, 6 digits)
    * `21`  Serial number (variable, up to 20 characters)
    * `414` GLN (fixed, 13 digits) — resolves a site, see `ThamaniDawa.Sites.get_site_by_gln/2`

  Per the GS1 General Specifications, a variable-length AI's value runs up
  to the FNC1/group-separator character (ASCII 29) when another AI
  follows, or to the end of the string when it's the last element.
  """

  @gs <<29>>

  @fixed_length_ais %{"01" => 14, "11" => 6, "17" => 6, "414" => 13}
  @variable_length_ais ~w(10 21)
  @known_ais Map.keys(@fixed_length_ais) ++ @variable_length_ais

  @field_by_ai %{
    "01" => :gtin,
    "10" => :batch_no,
    "11" => :production_date,
    "17" => :expiry_date,
    "21" => :serial,
    "414" => :gln
  }

  @empty_result %{
    gtin: nil,
    batch_no: nil,
    production_date: nil,
    expiry_date: nil,
    serial: nil,
    gln: nil
  }

  @doc """
  Parses a raw GS1 element string into `%{gtin:, batch_no:, production_date:,
  expiry_date:, serial:, gln:}`. Fields absent from the scanned data are
  `nil`; `production_date`/`expiry_date` come back as `Date` structs.

  Returns `{:error, reason}` if the string contains an AI this system
  doesn't handle, or a value that doesn't parse (wrong length, non-numeric
  digits, invalid date).
  """
  def parse(data) when is_binary(data) do
    with {:ok, ais} <- do_parse(strip_gs(data), %{}) do
      build_result(ais)
    end
  end

  defp do_parse(<<>>, acc), do: {:ok, acc}

  defp do_parse(rest, acc) do
    with {:ok, ai, rest} <- take_ai(rest),
         {:ok, value, rest} <- take_value(ai, rest) do
      do_parse(strip_gs(rest), Map.put(acc, ai, value))
    end
  end

  defp take_ai("414" <> rest), do: {:ok, "414", rest}
  defp take_ai(<<ai::binary-size(2), rest::binary>>) when ai in @known_ais, do: {:ok, ai, rest}
  defp take_ai(rest), do: {:error, {:unrecognized_ai, rest}}

  defp take_value(ai, rest) do
    case Map.fetch(@fixed_length_ais, ai) do
      {:ok, length} -> take_fixed_value(ai, rest, length)
      :error -> take_variable_value(rest)
    end
  end

  defp take_fixed_value(_ai, rest, length) when byte_size(rest) >= length do
    <<value::binary-size(length), remainder::binary>> = rest
    {:ok, value, remainder}
  end

  defp take_fixed_value(ai, _rest, _length), do: {:error, {:invalid_length, ai}}

  defp take_variable_value(rest) do
    case String.split(rest, @gs, parts: 2) do
      [value, remainder] -> {:ok, value, remainder}
      [value] -> {:ok, value, ""}
    end
  end

  defp strip_gs(@gs <> rest), do: strip_gs(rest)
  defp strip_gs(rest), do: rest

  defp build_result(ais) do
    Enum.reduce_while(@field_by_ai, {:ok, @empty_result}, fn {ai, field}, {:ok, acc} ->
      case Map.fetch(ais, ai) do
        :error ->
          {:cont, {:ok, acc}}

        {:ok, raw} ->
          case cast_field(field, raw) do
            {:ok, value} -> {:cont, {:ok, Map.put(acc, field, value)}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
      end
    end)
  end

  defp cast_field(field, raw) when field in [:gtin, :gln], do: validate_digits(raw)
  defp cast_field(field, raw) when field in [:production_date, :expiry_date], do: parse_date(raw)
  defp cast_field(_field, raw), do: {:ok, raw}

  defp validate_digits(raw) do
    if String.match?(raw, ~r/^\d+$/) do
      {:ok, raw}
    else
      {:error, {:invalid_digits, raw}}
    end
  end

  defp parse_date(<<yy::binary-size(2), mm::binary-size(2), dd::binary-size(2)>> = raw) do
    with {yy, ""} <- Integer.parse(yy),
         {mm, ""} <- Integer.parse(mm),
         {dd, ""} <- Integer.parse(dd) do
      build_date(century(yy) + yy, mm, dd)
    else
      _ -> {:error, {:invalid_date, raw}}
    end
  end

  defp century(yy) when yy <= 49, do: 2000
  defp century(_yy), do: 1900

  # GS1 rule: day `00` means the last day of the given month.
  defp build_date(year, month, 0) do
    case Date.new(year, month, 1) do
      {:ok, date} -> build_date(year, month, Date.days_in_month(date))
      {:error, reason} -> {:error, {:invalid_date, reason}}
    end
  end

  defp build_date(year, month, day) do
    case Date.new(year, month, day) do
      {:ok, date} -> {:ok, date}
      {:error, reason} -> {:error, {:invalid_date, reason}}
    end
  end
end
