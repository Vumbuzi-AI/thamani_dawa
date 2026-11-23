defmodule ThamaniDawaWeb.ManufacturerSerialExportController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Manufacturing.SerialExport

  def show(conn, %{"gtin" => gtin, "batch_id" => batch_id}) do
    organization_id = conn.assigns.current_scope.organization_id
    product = Manufacturing.get_product_by_gtin!(organization_id, gtin)
    batch = Manufacturing.get_batch!(organization_id, batch_id)

    if batch.manufacturer_product_id != product.id do
      raise Ecto.NoResultsError, queryable: ThamaniDawa.Manufacturing.Batch
    end

    serials = Manufacturing.list_serials(organization_id, batch.id)
    body = SerialExport.batch_csv(product, batch, serials)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header(
      "content-disposition",
      ~s(attachment; filename="#{gtin}-#{batch.batch_no}-serials.csv")
    )
    |> send_resp(200, body)
  end
end
