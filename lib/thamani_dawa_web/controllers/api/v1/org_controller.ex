defmodule ThamaniDawaWeb.Api.V1.OrgController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Dashboards
  alias ThamaniDawa.Payments
  alias ThamaniDawa.Reports
  alias ThamaniDawaWeb.Api.FallbackController
  alias ThamaniDawaWeb.Api.Params
  alias ThamaniDawaWeb.Api.Response
  alias ThamaniDawaWeb.Api.Serializer
  alias ThamaniDawaWeb.Api.V1.Helpers
  alias ThamaniDawaWeb.Plugs.RequirePortal

  import Helpers

  action_fallback FallbackController

  plug RequirePortal, :org

  def dashboard(conn, params) do
    site_id =
      case Params.integer(params["site_id"]) do
        {:ok, id} -> id
        :error -> nil
      end

    stats =
      Dashboards.admin_stats(org_id(conn), site_id, date_range(params), params["search"])

    Response.data(conn, %{
      from: Date.to_iso8601(elem(date_range(params), 0)),
      to: Date.to_iso8601(elem(date_range(params), 1)),
      stats: Serializer.stats(stats)
    })
  end

  def earnings(conn, _params) do
    by_site =
      conn
      |> org_id()
      |> Payments.site_earnings_by_site()
      |> Enum.map(fn {site_id, amount} ->
        %{site_id: site_id, amount: Decimal.to_string(amount, :normal)}
      end)

    Response.data(conn, %{
      total: Decimal.to_string(Payments.organization_earnings(org_id(conn)), :normal),
      by_site: by_site,
      by_payment_method: Serializer.series(Payments.sales_by_payment_method(org_id(conn))),
      profitability:
        Enum.map(Reports.site_profitability(org_id(conn)), fn row ->
          %{
            site: Serializer.site(row.site),
            revenue: Decimal.to_string(row.revenue, :normal),
            cost_of_goods: Decimal.to_string(row.cost_of_goods, :normal),
            profit: Decimal.to_string(row.profit, :normal)
          }
        end)
    })
  end

  defp date_range(%{"from" => from, "to" => to}) when is_binary(from) and is_binary(to) do
    with {:ok, from} <- Date.from_iso8601(from),
         {:ok, to} <- Date.from_iso8601(to),
         {:ok, range} <- Dashboards.validate_custom_range(from, to) do
      range
    else
      _ -> Dashboards.range_dates("this_month")
    end
  end

  defp date_range(params), do: Dashboards.range_dates(params["range"])
end
