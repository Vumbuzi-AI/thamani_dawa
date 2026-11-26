defmodule ThamaniDawaWeb.ManufacturerSerialExportController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Manufacturing

  def show(conn, %{"gtin" => gtin, "batch_id" => batch_no}) do
    organization_id = conn.assigns.current_scope.organization_id
    product = Manufacturing.get_product_by_gtin!(organization_id, gtin)

    with %{} = batch <-
           Manufacturing.get_batch_by_product_and_no(organization_id, product.id, batch_no),
         serials when serials != [] <- Manufacturing.list_serials(organization_id, batch.id) do
      rows =
        Enum.map(
          serials,
          &[product.gtin, batch.batch_no, batch.production_date, batch.expiry_date, &1.serial]
        )

      body =
        [["gtin", "batch", "production_date", "expiry_date", "serial"] | rows]
        |> Enum.map_join("", fn row -> Enum.map_join(row, ",", &csv_cell/1) <> "\r\n" end)

      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="#{product.gtin}-#{safe_filename(batch_no)}-serials.csv")
      )
      |> send_resp(200, body)
    else
      _ ->
        conn
        |> put_flash(:error, "No locally generated serials are available for this batch.")
        |> redirect(to: ~p"/manufacturer/products/#{product.gtin}/serials")
    end
  end

  defp safe_filename(value), do: String.replace(value, ~r/[^A-Za-z0-9_-]/, "_")

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
