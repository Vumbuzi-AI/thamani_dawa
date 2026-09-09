defmodule ThamaniDawaWeb.SerialExportController do
  @moduledoc """
  CSV export of one SSCC group's serialised codes (ui.md §13).

  Streamed straight from the database to the socket: a serialised run can hold
  millions of rows, and a LiveView request must never be held open building
  one (§13).

  Authorization is checked here again rather than trusted from the screen that
  produced the link, and every query is organization-scoped — a download URL is
  as reachable as any other route.
  """

  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Serialisation

  @headers ~w(pallet_sscc shipper_sscc shipper_serial gtin serial batch
              production_date expiry_date order_number)a

  def export(conn, %{"gtin" => gtin, "sscc_id" => sscc_id}) do
    scope = conn.assigns[:current_scope]

    if authorized?(scope) do
      group = Serialisation.get_group!(scope.organization_id, sscc_id)

      conn =
        conn
        |> put_resp_content_type("text/csv")
        |> put_resp_header(
          "content-disposition",
          ~s(attachment; filename="serials-#{slug(gtin)}-#{group.code}.csv")
        )
        |> send_chunked(200)

      Repo.transaction(fn ->
        Enum.reduce_while(rows(scope, group), conn, &chunk_row/2)
      end)
      |> case do
        {:ok, conn} -> conn
        {:error, _reason} -> conn
      end
    else
      conn
      |> put_flash(:error, "You don't have access to that export.")
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  defp rows(scope, group) do
    Stream.concat(
      [csv_line(Enum.map(@headers, &to_string/1))],
      Stream.map(Serialisation.stream_group_rows(scope.organization_id, group), fn row ->
        @headers |> Enum.map(&Map.get(row, &1)) |> csv_line()
      end)
    )
  end

  defp chunk_row(line, conn) do
    case chunk(conn, line) do
      {:ok, conn} -> {:cont, conn}
      {:error, :closed} -> {:halt, conn}
    end
  end

  defp authorized?(%Scope{} = scope) do
    Scope.admin?(scope) and Organizations.distributor?(scope.organization_id)
  end

  defp authorized?(_scope), do: false

  # Every value is quoted, and an identifier is prefixed with a tab so a
  # spreadsheet opens `06164005056791` as text rather than eating its leading
  # zero (ui.md §13).
  defp csv_line(values) do
    values
    |> Enum.map_join(",", &csv_value/1)
    |> Kernel.<>("\r\n")
  end

  defp csv_value(nil), do: ~s("")
  defp csv_value(%Date{} = date), do: ~s("#{Date.to_iso8601(date)}")

  defp csv_value(value) when is_binary(value) do
    escaped = String.replace(value, ~s("), ~s(""))

    if numeric?(value), do: ~s("\t#{escaped}"), else: ~s("#{escaped}")
  end

  defp csv_value(value), do: ~s("#{value}")

  defp numeric?(value), do: String.match?(value, ~r/^\d+$/)

  defp slug(value), do: String.replace(value, ~r/[^A-Za-z0-9]+/, "-")
end
