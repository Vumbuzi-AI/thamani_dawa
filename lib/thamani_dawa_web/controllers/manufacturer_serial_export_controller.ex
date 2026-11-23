defmodule ThamaniDawaWeb.ManufacturerSerialExportController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Manufacturing

  # `batch_id` in the route carries the GS1 batch number. Serials are read
  # from the GS1 member API (one batch lookup, one serial lookup).
  def show(conn, %{"gtin" => gtin, "batch_id" => batch_no}) do
    organization_id = conn.assigns.current_scope.organization_id
    product = Manufacturing.get_product_by_gtin!(organization_id, gtin)

    with {:ok, batches} <- Manufacturing.fetch_product_batches(organization_id, product.gtin),
         %{} = batch <- Enum.find(batches, &(&1.batch_no == batch_no)),
         {:ok, serials} <-
           Manufacturing.fetch_batch_serials(organization_id, product.gtin, batch_no) do
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
        |> put_flash(:error, "Couldn't load this batch's serials from GS1. Try again shortly.")
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
