defmodule ThamaniDawaWeb.ManufacturerSsccExportController do
  @moduledoc """
  Streams a shipper SSCC's serials as a formula-injection-safe CSV. Access
  is enforced by the `:require_manufacturer_user` plug; the SSCC is always
  looked up within the signed-in user's organization.
  """

  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Manufacturing

  def show(conn, %{"id" => id}) do
    organization_id = conn.assigns.current_scope.organization_id
    sscc = Manufacturing.get_sscc_group!(organization_id, id)
    serials = Manufacturing.list_serials_for_sscc(organization_id, sscc.id)
    filename = "sscc-#{sscc.code}.csv"

    rows =
      for serial <- serials do
        [sscc.code, sscc.gtin, sscc.batch, serial.serial]
      end

    body =
      [["sscc", "gtin", "batch", "serial"] | rows]
      |> Enum.map_join("", fn row -> Enum.map_join(row, ",", &csv_cell/1) <> "\r\n" end)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, body)
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
