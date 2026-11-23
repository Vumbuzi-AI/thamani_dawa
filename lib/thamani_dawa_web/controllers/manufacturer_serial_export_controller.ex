defmodule ThamaniDawaWeb.ManufacturerSerialExportController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Manufacturing

  def show(conn, %{"gtin" => gtin, "batch_id" => batch_id}) do
    organization_id = conn.assigns.current_scope.organization_id
    product = Manufacturing.get_product_by_gtin!(organization_id, gtin)
    batch = Manufacturing.get_batch!(organization_id, batch_id)

    if batch.manufacturer_product_id != product.id do
      raise Ecto.NoResultsError, queryable: ThamaniDawa.Manufacturing.Batch
    end

    rows =
      Manufacturing.list_serials(organization_id, batch.id)
      |> Enum.map(
        &[product.gtin, batch.batch_no, batch.production_date, batch.expiry_date, &1.serial]
      )

    body =
      [["gtin", "batch", "production_date", "expiry_date", "serial"] | rows]
      |> Enum.map_join("", fn row -> Enum.map_join(row, ",", &csv_cell/1) <> "\r\n" end)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header(
      "content-disposition",
      ~s(attachment; filename="#{gtin}-#{batch.batch_no}-serials.csv")
    )
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

    if String.starts_with?(value, ["=", "+", "-", "@"]) do
      "'" <> value
    else
      value
    end
  end
end
