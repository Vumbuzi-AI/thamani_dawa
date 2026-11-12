defmodule ThamaniDawaWeb.ProductImportTemplateController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Distributor.Reports
  alias ThamaniDawa.Products.Importer

  def show(conn, _params) do
    if Scope.admin?(conn.assigns.current_scope) do
      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="product-import-template.csv")
      )
      |> send_resp(200, Reports.to_csv([Importer.template_headers()]))
    else
      send_resp(conn, 403, "Forbidden")
    end
  end
end
