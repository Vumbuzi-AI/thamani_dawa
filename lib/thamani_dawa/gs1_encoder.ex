defmodule ThamaniDawa.GS1Encoder do
  @moduledoc """
  Encodes a `Batch` struct into standard GS1 Data Matrix element strings and
  human-readable AI representations per the GS1 General Specifications (§6 clean spec).

  AI Order and Formatting:
    * AI 01: GTIN, exactly 14 digits (zero-padded). Fixed length (14 digits), no separator after it.
    * AI 10: Batch/lot number, variable length. GS-terminated if followed by another AI.
    * AI 11: Production date, YYMMDD, fixed 6 digits (omitted if nil).
    * AI 17: Expiry date, YYMMDD, fixed 6 digits.
    * AI 21: Serial number, variable length (emitted only if present and non-empty).

  No redundant separators before fixed-length AIs; no leading FNC1 byte in raw payload.
  """

  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.Gtin

  @gs <<29>>

  @doc """
  Generates the raw GS1 element string (using ASCII 29 group separator bytes).
  100% compatible with `ThamaniDawa.GS1Decoder.parse/1`.
  """
  def encode_raw(%Batch{} = batch) do
    gtin = format_gtin(batch.gtin || (batch.product && batch.product.gtin))
    batch_no = batch.batch_no || ""
    mfg_date = format_date(batch.manufacture_date)
    exp_date = format_date(batch.expiry_date)
    serial = batch.serial

    "01"
    |> Kernel.<>(gtin)
    |> append_ai_10(batch_no, mfg_date, exp_date, serial)
    |> append_ai_11(mfg_date)
    |> append_ai_17(exp_date)
    |> append_ai_21(serial)
  end

  defp append_ai_10(acc, batch_no, mfg_date, exp_date, serial) do
    has_more? =
      not is_nil(mfg_date) or not is_nil(exp_date) or (is_binary(serial) and serial != "")

    sep = if has_more?, do: @gs, else: ""
    acc <> "10" <> batch_no <> sep
  end

  defp append_ai_11(acc, nil), do: acc
  defp append_ai_11(acc, mfg_date), do: acc <> "11" <> mfg_date

  defp append_ai_17(acc, nil), do: acc
  defp append_ai_17(acc, exp_date), do: acc <> "17" <> exp_date

  defp append_ai_21(acc, serial) when is_binary(serial) and serial != "",
    do: acc <> "21" <> serial

  defp append_ai_21(acc, _serial), do: acc

  @doc """
  Generates human-readable parenthesized AI representation for barcode text and labels:
  `"(01)00614141000012(10)LOT123(11)240115(17)260228(21)SN0001"`
  """
  def human_readable(%Batch{} = batch) do
    gtin = format_gtin(batch.gtin || (batch.product && batch.product.gtin))
    batch_no = batch.batch_no || ""
    mfg_date = format_date(batch.manufacture_date)
    exp_date = format_date(batch.expiry_date)
    serial = batch.serial

    parts = [
      "(01)" <> gtin,
      "(10)" <> batch_no,
      if(mfg_date, do: "(11)" <> mfg_date),
      if(exp_date, do: "(17)" <> exp_date),
      if(is_binary(serial) and serial != "", do: "(21)" <> serial)
    ]

    parts |> Enum.reject(&is_nil/1) |> Enum.join()
  end

  @doc """
  Formats string for bwip-js barcode generator.
  """
  def bwipjs_text(%Batch{} = batch), do: human_readable(batch)

  defp format_gtin(gtin) when is_binary(gtin) do
    case Gtin.normalize(gtin) do
      {:ok, normalized} -> String.pad_leading(normalized, 14, "0")
      _ -> String.pad_leading(gtin, 14, "0")
    end
  end

  defp format_gtin(_), do: String.duplicate("0", 14)

  defp format_date(%Date{} = date) do
    yy = date.year |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    mm = date.month |> Integer.to_string() |> String.pad_leading(2, "0")
    dd = date.day |> Integer.to_string() |> String.pad_leading(2, "0")
    yy <> mm <> dd
  end

  defp format_date(_), do: nil
end
