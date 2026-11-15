defmodule ThamaniDawa.PpbRegistryStub do
  @moduledoc """
  Stands in for the PPB facilities register's AJAX endpoints during tests.

  Answers both calls `ThamaniDawa.Ppb` makes: the DataTables-style search
  (`fetch=facilities`) and the per-facility detail fragment
  (`search_details=facility`). A small canned dataset covers the cases tests
  need to exercise: a uniquely-matching retail facility, a uniquely-matching
  wholesale facility (for the distributor PPB path), two facilities that
  share the same masked license (to exercise the `:ambiguous` path), a
  facility whose licence status is not `VALID` (to exercise the
  `:license_inactive` path), and a search term that matches nothing
  (`:name_not_found`).
  """

  @behaviour Plug

  @facilities [
    %{
      id: "1",
      name: "UNIQUE PHARMACY LTD",
      type: "RETAIL",
      masked_license: "AB1****9999",
      status: "VALID"
    },
    %{
      id: "2",
      name: "AMBIGUOUS PHARMACY LTD",
      type: "RETAIL",
      masked_license: "CD2****1111",
      status: "VALID"
    },
    %{
      id: "3",
      name: "AMBIGUOUS PHARMACY BRANCH",
      type: "RETAIL",
      masked_license: "CD2****1111",
      status: "VALID"
    },
    %{
      id: "4",
      name: "UNIQUE DISTRIBUTOR LTD",
      type: "WHOLESALE",
      masked_license: "EF3****2222",
      status: "VALID"
    },
    %{
      id: "5",
      name: "INACTIVE PHARMACY LTD",
      type: "RETAIL",
      masked_license: "GH4****3333",
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

  defp handle(conn, %{"fetch" => "facilities"} = params, _opts) do
    if valid_datatables_request?(params) do
      search = params |> Map.get("search", %{}) |> Map.get("value", "") |> String.downcase()

      rows =
        @facilities
        |> Enum.filter(&String.contains?(String.downcase(&1.name), search))
        |> Enum.map(&row/1)

      body = %{
        "draw" => "1",
        "recordsTotal" => "#{length(@facilities)}",
        "recordsFiltered" => "#{length(rows)}",
        "data" => rows
      }

      conn
      # The live PPB endpoint returns JSON with a text/html content type.
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(200, Jason.encode!(body))
    else
      Plug.Conn.send_resp(conn, 400, "incomplete DataTables request")
    end
  end

  defp handle(conn, %{"search_details" => "facility", "id" => id}, _opts) do
    facility = Enum.find(@facilities, &(&1.id == id))

    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(200, detail_html(facility))
  end

  defp row(facility) do
    [
      facility.name,
      facility.type,
      "<span class='label label-success'>Status: Active</span>",
      "<a rel='#{facility.id}' data-toggle='modal'>View Details</a>"
    ]
  end

  defp valid_datatables_request?(params) do
    Map.get(params, "search", %{})["regex"] == "false" and
      Map.get(params, "order", %{})["0"] == %{"column" => "0", "dir" => "asc"} and
      Enum.all?(0..3, fn index ->
        params
        |> Map.get("columns", %{})
        |> Map.get(Integer.to_string(index), %{})
        |> Map.take(["data", "searchable", "orderable", "search"])
        |> then(fn column ->
          column["data"] == Integer.to_string(index) and
            column["searchable"] == "true" and
            column["orderable"] == "true" and
            column["search"] == %{"regex" => "false", "value" => ""}
        end)
      end)
  end

  defp detail_html(nil), do: ""

  defp detail_html(facility) do
    """
    <b style="font-size:20px;">#{facility.name}</b>
    <a class="list-group-item text-boldest">License Number: #{facility.masked_license}</a>
    <a class="list-group-item text-boldest">Ownership : PRIVATE COMPANY (LIMITED)</a>
    <a class="list-group-item text-boldest">License Type: #{facility.type}</a>
    <a class="list-group-item text-boldest">Street: TEST STREET</a>
    <a class="list-group-item text-boldest">County : Nairobi</a>
    <span class="label label-success">Licence Status: #{facility.status}</span>
    <span class="text-boldest">Valid Till: 2026-12-31</span>
    """
  end
end
