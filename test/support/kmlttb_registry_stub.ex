defmodule ThamaniDawa.KmlttbRegistryStub do
  @moduledoc """
  Stands in for KMLTTB's public lab facilities register during tests.

  Answers both calls `ThamaniDawa.Kmlttb` makes: the search table (a
  `search` query param) and the per-facility detail page (an `id` query
  param). Mirrors `ThamaniDawa.PpbRegistryStub`'s canned-dataset shape, but
  KMLTTB's real license numbers are unmasked, so `verify_license/2`
  compares them exactly — the dataset here includes a uniquely-matching
  facility, two facilities sharing a name prefix (for the `:ambiguous`
  path, keyed off entering a license that matches both), one with a
  non-`"ACTIVE"` status (for `:license_inactive`), and a search term that
  matches nothing (`:name_not_found`).
  """

  @behaviour Plug

  @facilities [
    %{
      id: "1",
      name: "UNIQUE LAB LTD",
      county: "NAIROBI",
      license_no: "L 01000/26",
      status: "ACTIVE"
    },
    %{
      id: "2",
      name: "AMBIGUOUS LAB MAIN",
      county: "NAIROBI",
      license_no: "L 02000/26",
      status: "ACTIVE"
    },
    %{
      id: "3",
      name: "AMBIGUOUS LAB BRANCH",
      county: "KIAMBU",
      license_no: "L 02000/26",
      status: "ACTIVE"
    },
    %{
      id: "4",
      name: "INACTIVE LAB LTD",
      county: "NAIROBI",
      license_no: "L 03000/26",
      status: "SUSPENDED"
    }
  ]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    conn = Plug.Conn.fetch_query_params(conn)
    handle(conn, conn.query_params, opts)
  end

  defp handle(conn, %{"search" => search}, _opts) do
    search = String.downcase(search)

    rows =
      @facilities
      |> Enum.filter(&String.contains?(String.downcase(&1.name), search))
      |> Enum.map_join(&row/1)

    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(200, table_html(rows))
  end

  defp handle(conn, %{"id" => id}, _opts) do
    facility = Enum.find(@facilities, &(&1.id == id))

    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(200, detail_html(facility))
  end

  defp row(facility) do
    """
    <tr>
    <td class="name-column">
    <a href="view_record.php?id=#{facility.id}" class="name-link">#{facility.name}</a>
    </td>
    <td class="text-center">B</td>
    <td class="text-center">#{facility.county}</td>
    <td class="text-center">2</td>
    <td class="text-center">2026</td>
    <td class="text-center">ACTIVE</td>
    </tr>
    """
  end

  defp table_html(rows) do
    """
    <table>
    <tbody>
    #{rows}
    </tbody>
    </table>
    """
  end

  defp detail_html(nil), do: ""

  defp detail_html(facility) do
    """
    <table class="details-table">
    <tr><th>Name</th><td><strong>#{facility.name}</strong></td></tr>
    <tr><th>File No</th><td>G#{facility.id}</td></tr>
    <tr><th>Type</th><td>2</td></tr>
    <tr><th>Class</th><td>B</td></tr>
    <tr><th>County</th><td>#{facility.county}</td></tr>
    <tr><th>Licence No</th><td>#{facility.license_no}</td></tr>
    <tr><th>Valid Until</th><td><strong>31 December 2026</strong></td></tr>
    <tr><th>Status</th><td>#{facility.status}</td></tr>
    </table>
    """
  end
end
