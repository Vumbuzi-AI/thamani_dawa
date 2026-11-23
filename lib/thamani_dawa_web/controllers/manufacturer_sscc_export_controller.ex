defmodule ThamaniDawaWeb.ManufacturerSsccExportController do
  @moduledoc """
  Streams a shipper SSCC's serials (fetched from the GS1 member API) as a formula-injection-safe CSV. Access
  is enforced by the `:require_manufacturer_user` plug; the SSCC is always
  looked up within the signed-in user's organization.
  """

  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Manufacturing

  def show(conn, %{"id" => id}) do
    organization_id = conn.assigns.current_scope.organization_id
    sscc = Manufacturing.get_sscc_group!(organization_id, id)

    case Manufacturing.fetch_sscc_serials(organization_id, sscc.code) do
      {:ok, serials} ->
        send_csv(conn, sscc, serials)

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Couldn't load this SSCC's serials from GS1. Try again shortly.")
        |> redirect(to: ~p"/manufacturer/sscc/#{sscc.id}/serials")
    end
  end

  defp send_csv(conn, sscc, serials) do
    filename = "sscc-#{sscc.code}.csv"

    rows =
      for serial <- serials do
        [sscc.code, serial.gtin, serial.batch, serial.serial]
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
