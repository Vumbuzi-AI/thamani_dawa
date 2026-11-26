defmodule ThamaniDawaWeb.ManufacturerSsccExportController do
  @moduledoc """
  Streams a shipper SSCC's packed serials as a formula-injection-safe CSV. Access
  is enforced by the `:require_manufacturer_user` plug; the SSCC is always
  looked up within the signed-in user's organization.
  """

  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Manufacturing

  def show(conn, %{"id" => id}) do
    organization_id = conn.assigns.current_scope.organization_id
    sscc = Manufacturing.get_sscc_group!(organization_id, id)
    serials = shipper_serials(organization_id, sscc)

    send_csv(conn, sscc, serials)
  end

  # Packed serials are the accurate SSCC contents in this context.
  defp shipper_serials(organization_id, sscc) do
    packed = sscc.packed_serials || []
    mirrored = for serial <- sscc.serials || [], do: serial.serial

    serial_values =
      cond do
        packed != [] ->
          packed

        mirrored != [] ->
          mirrored

        true ->
          organization_id
          |> Manufacturing.list_verified_shipper_serials(sscc.id)
          |> Enum.map(& &1.serial)
      end

    serial_values
    |> Enum.uniq()
    |> Enum.map(fn serial ->
      %{
        gtin: sscc.gtin,
        batch: sscc.batch,
        production_date: sscc.production_date,
        expiry_date: sscc.expiry_date,
        serial: serial
      }
    end)
  end

  defp send_csv(conn, sscc, serials) do
    filename = "sscc-#{safe_filename(sscc.code)}-serials.csv"

    rows =
      Enum.map(serials, fn serial ->
        [
          {:id, serial.gtin},
          serial.batch,
          serial.production_date,
          serial.expiry_date,
          serial.serial
        ]
      end)

    body =
      [
        ["Shipper SSCC", sscc.code],
        ["gtin", "batch", "production_date", "expiry_date", "serial"] | rows
      ]
      |> Enum.map_join("", fn row -> Enum.map_join(row, ",", &csv_cell/1) <> "\r\n" end)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, body)
  end

  defp safe_filename(value), do: value |> to_string() |> String.replace(~r/[^A-Za-z0-9_-]/, "_")

  defp csv_cell({:id, value}), do: csv_identifier(value)
  defp csv_cell(value), do: csv_text_cell(value)

  # Keep long numeric identifiers readable in spreadsheets (avoid Excel scientific notation).
  defp csv_identifier(value) do
    value = value |> to_string() |> String.replace("\"", "\"\"")
    "=\"\"#{value}\"\""
  end

  defp csv_text_cell(value) do
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
