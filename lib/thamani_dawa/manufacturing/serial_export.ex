defmodule ThamaniDawa.Manufacturing.SerialExport do
  @moduledoc """
  Rows and formula-injection-safe CSV for serial exports: a batch's serials
  and a shipper SSCC's serials. Shared by the web export controllers and
  the JSON API.
  """

  @batch_header ["gtin", "batch", "production_date", "expiry_date", "serial"]
  @sscc_header ["sscc", "gtin", "batch", "serial"]

  def batch_header, do: @batch_header
  def sscc_header, do: @sscc_header

  @doc "One row per serial of a batch, in `batch_header/0` order."
  def batch_rows(product, batch, serials) do
    Enum.map(
      serials,
      &[product.gtin, batch.batch_no, batch.production_date, batch.expiry_date, &1.serial]
    )
  end

  @doc "One row per serial packed under a shipper SSCC, in `sscc_header/0` order."
  def sscc_rows(sscc, serials) do
    for serial <- serials, do: [sscc.code, sscc.gtin, sscc.batch, serial.serial]
  end

  @doc "The batch export as CSV, header first."
  def batch_csv(product, batch, serials),
    do: to_csv([@batch_header | batch_rows(product, batch, serials)])

  @doc "The SSCC export as CSV, header first."
  def sscc_csv(sscc, serials), do: to_csv([@sscc_header | sscc_rows(sscc, serials)])

  @doc "CRLF-separated CSV with quoting and a leading `'` on formula-like cells."
  def to_csv(rows) do
    Enum.map_join(rows, "", fn row -> Enum.map_join(row, ",", &csv_cell/1) <> "\r\n" end)
  end

  defp csv_cell(value) do
    value = safe_cell(value)

    if String.contains?(value, [",", "\"", "\n", "\r"]),
      do: "\"" <> String.replace(value, "\"", "\"\"") <> "\"",
      else: value
  end

  defp safe_cell(nil), do: ""

  defp safe_cell(value) do
    value = to_string(value)
    if String.starts_with?(value, ["=", "+", "-", "@"]), do: "'" <> value, else: value
  end
end
