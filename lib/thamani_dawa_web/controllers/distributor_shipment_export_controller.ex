defmodule ThamaniDawaWeb.DistributorShipmentExportController do
  @moduledoc """
  Streams every scanned unit of a shipment as a formula-injection-safe CSV.
  Access is enforced by the `:require_distributor_user` plug; the shipment is
  always looked up within the signed-in user's organization.
  """

  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Distributor.Reports

  def show(conn, %{"id" => id}) do
    shipment = Distributor.get_shipment!(conn.assigns.current_scope.organization_id, id)
    filename = "shipment-#{shipment.reference}-#{Date.to_iso8601(Date.utc_today())}.csv"

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, shipment |> Reports.export_rows() |> Reports.to_csv())
  end
end
