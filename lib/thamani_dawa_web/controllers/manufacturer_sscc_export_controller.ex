defmodule ThamaniDawaWeb.ManufacturerSsccExportController do
  @moduledoc """
  Streams a shipper SSCC's serials as a formula-injection-safe CSV. Access
  is enforced by the `:require_manufacturer_user` plug; the SSCC is always
  looked up within the signed-in user's organization.
  """

  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Manufacturing.SerialExport

  def show(conn, %{"id" => id}) do
    organization_id = conn.assigns.current_scope.organization_id
    sscc = Manufacturing.get_sscc_group!(organization_id, id)
    serials = Manufacturing.list_serials_for_sscc(organization_id, sscc.id)
    filename = "sscc-#{sscc.code}.csv"

    body = SerialExport.sscc_csv(sscc, serials)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, body)
  end
end
