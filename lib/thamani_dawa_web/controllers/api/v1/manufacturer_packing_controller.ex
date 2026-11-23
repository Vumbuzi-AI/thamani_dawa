defmodule ThamaniDawaWeb.Api.V1.ManufacturerPackingController do
  @moduledoc """
  Packing flows of the manufacturer portal for the mobile app.

  Aggregations pack primary serials into an existing shipper SSCC: create a
  draft for an SSCC, scan serials into it, submit, then approve (which
  links the serials and fires the EPCIS Pack event) or reject. Posting
  `serials` with the create does what the web form does: every serial must
  be valid for the SSCC, and the aggregation is created already submitted.

  Shipments are the web portal's manufacturer-tier shipments
  (`ThamaniDawa.Distributor` with `participant_tier: "manufacturer"`):
  staff create a draft, mobile packers fill and submit it, and staff
  approve it, which issues SSCCs and fires the EPCIS shipping event.
  """

  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Manufacturing
  alias ThamaniDawaWeb.Api.Params
  alias ThamaniDawaWeb.Api.Response
  alias ThamaniDawaWeb.Api.Serializer
  alias ThamaniDawaWeb.Api.V1.Helpers
  alias ThamaniDawaWeb.Api.V1.ManufacturerFallback
  alias ThamaniDawaWeb.Plugs.RequireIdempotency
  alias ThamaniDawaWeb.Plugs.RequirePortal

  import Helpers

  action_fallback ManufacturerFallback

  @statuses ~w(draft submitted approved rejected)

  plug RequirePortal, :manufacturer

  plug RequireIdempotency
       when action in [
              :create_aggregation,
              :scan,
              :submit_aggregation,
              :approve_aggregation,
              :reject_aggregation,
              :create_shipment,
              :approve_shipment
            ]

  # Aggregations

  def aggregations(conn, params) do
    result =
      Manufacturing.list_aggregations(org_id(conn), %{
        status: status(params["status"]),
        search: params["search"],
        page: page(params)
      })

    Response.page(conn, Enum.map(result.entries, &Serializer.aggregation/1), meta(result))
  end

  # The SSCCs an aggregation can target.
  def aggregation_ssccs(conn, _params) do
    ssccs = Manufacturing.available_ssccs_for_aggregation(org_id(conn))
    Response.data(conn, Enum.map(ssccs, &Serializer.sscc/1))
  end

  # Checks a serial against an SSCC without saving anything.
  def classify(conn, params) do
    with {:ok, sscc} <- load_sscc(conn, params["sscc_id"]),
         {:ok, serial} <- serial_param(params["serial"]) do
      {status, _record} = Manufacturing.classify_serial(org_id(conn), sscc, serial)
      Response.data(conn, %{serial: serial, validation_status: status})
    end
  end

  def create_aggregation(conn, params) do
    idempotent(conn, fn ->
      with {:ok, sscc} <- load_sscc(conn, params["sscc_id"]),
           {:ok, aggregation} <- create(conn, sscc, params["serials"]) do
        {:ok, 201, %{data: aggregation_body(conn, aggregation.id)}}
      end
    end)
  end

  def show_aggregation(conn, %{"id" => id}) do
    with {:ok, aggregation} <- load_aggregation(conn, id) do
      Response.data(conn, Serializer.aggregation(aggregation))
    end
  end

  # Scans one serial into a draft. The item is kept even when it is not
  # valid for the SSCC, so it can be seen and fixed on review.
  def scan(conn, %{"id" => id} = params) do
    idempotent(conn, fn ->
      with {:ok, aggregation} <- load_aggregation(conn, id),
           :ok <- draft(aggregation),
           {:ok, serial} <- serial_param(params["serial"]),
           :ok <- not_scanned(aggregation, serial),
           {:ok, _item} <-
             Manufacturing.scan_aggregation_item(org_id(conn), aggregation, serial) do
        {:ok, 201, %{data: aggregation_body(conn, aggregation.id)}}
      end
    end)
  end

  def submit_aggregation(conn, %{"id" => id}) do
    idempotent(conn, fn ->
      with {:ok, aggregation} <- load_aggregation(conn, id),
           :ok <- has_items(aggregation),
           {:ok, submitted} <- Manufacturing.submit_aggregation(org_id(conn), aggregation.id) do
        {:ok, 200, %{data: Serializer.aggregation(submitted)}}
      end
    end)
  end

  def approve_aggregation(conn, %{"id" => id}) do
    idempotent(conn, fn ->
      with {:ok, aggregation} <- load_aggregation(conn, id),
           {:ok, approved} <-
             conn
             |> org_id()
             |> Manufacturing.approve_aggregation(scope(conn).user, aggregation.id)
             |> invalid_items() do
        {:ok, 200, %{data: aggregation_body(conn, approved.id)}}
      end
    end)
  end

  def reject_aggregation(conn, %{"id" => id} = params) do
    idempotent(conn, fn ->
      with {:ok, aggregation} <- load_aggregation(conn, id),
           {:ok, rejected} <-
             Manufacturing.reject_aggregation(
               org_id(conn),
               scope(conn).user,
               aggregation.id,
               params["reason"]
             ) do
        {:ok, 200, %{data: Serializer.aggregation(rejected)}}
      end
    end)
  end

  # Shipments

  def shipments(conn, params) do
    result =
      Distributor.list_shipments(org_id(conn), %{
        participant_tier: "manufacturer",
        status: status(params["status"]),
        search: params["search"],
        date_from: date(params["date_from"]),
        date_to: date(params["date_to"]),
        page: page(params)
      })

    Response.page(conn, Enum.map(result.entries, &Serializer.shipment/1), meta(result))
  end

  def create_shipment(conn, params) do
    idempotent(conn, fn ->
      attrs =
        params
        |> Map.take(["order_number", "origin_gln", "destination_gln"])
        |> Map.put_new_lazy("origin_gln", fn -> current_site_gln(conn) end)

      with {:ok, shipment} <-
             Distributor.create_shipment(org_id(conn), scope(conn).user, attrs, "manufacturer") do
        {:ok, 201, %{data: shipment_body(conn, shipment.id)}}
      end
    end)
  end

  def show_shipment(conn, %{"id" => id}) do
    with {:ok, shipment} <- load_shipment(conn, id) do
      Response.data(conn, Serializer.shipment(shipment))
    end
  end

  # Approving a submitted shipment issues one SSCC per shipper and fires the
  # manufacturer EPCIS shipping event. Approving twice answers with the
  # approved shipment.
  def approve_shipment(conn, %{"id" => id}) do
    idempotent(conn, fn ->
      with {:ok, shipment} <- load_shipment(conn, id) do
        approve(conn, shipment)
      end
    end)
  end

  defp approve(_conn, %{status: "approved"} = shipment),
    do: {:ok, 200, %{data: Serializer.shipment(shipment)}}

  defp approve(conn, shipment) do
    case Distributor.approve_shipment(org_id(conn), scope(conn).user, shipment.id) do
      {:ok, approved} -> {:ok, 200, %{data: shipment_body(conn, approved.id)}}
      # Approved by someone else meanwhile. The context rolled its
      # transaction back, so nothing more can be read in this one.
      {:already_approved, _shipment} -> {:error, {:invalid_state, "approved"}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Like the web form, the origin defaults to the user's current site.
  defp current_site_gln(conn) do
    case current_site(conn) do
      {:ok, site} -> site.gln
      :none -> nil
    end
  end

  defp create(conn, sscc, nil),
    do: Manufacturing.create_aggregation(org_id(conn), scope(conn).user, sscc.id)

  defp create(conn, sscc, serials) when is_list(serials) do
    serials = serials |> Enum.map(&String.trim(to_string(&1))) |> Enum.reject(&(&1 == ""))

    with :ok <- some_serials(serials),
         :ok <- unique(serials),
         :ok <- all_valid(conn, sscc, serials) do
      Manufacturing.create_submitted_aggregation(org_id(conn), scope(conn).user, sscc.id, serials)
    end
  end

  defp create(_conn, _sscc, _serials), do: {:error, :bad_request}

  defp some_serials([]), do: {:error, :no_items}
  defp some_serials(_serials), do: :ok

  defp unique(serials) do
    if length(Enum.uniq(serials)) == length(serials), do: :ok, else: {:error, :duplicate_serial}
  end

  defp all_valid(conn, sscc, serials) do
    invalid =
      for serial <- serials,
          {status, _record} = Manufacturing.classify_serial(org_id(conn), sscc, serial),
          status != "ok",
          do: %{serial: serial, validation_status: status}

    if invalid == [], do: :ok, else: {:error, {:invalid_items, invalid}}
  end

  defp invalid_items({:error, {:invalid, items}}), do: {:error, {:invalid_items, items}}
  defp invalid_items(result), do: result

  defp draft(%{status: "draft"}), do: :ok
  defp draft(%{status: status}), do: {:error, {:invalid_state, status}}

  defp has_items(%{items: [_ | _]}), do: :ok
  defp has_items(%{status: "draft"}), do: {:error, :no_items}
  defp has_items(_aggregation), do: :ok

  defp not_scanned(aggregation, serial) do
    if Enum.any?(aggregation.items, &(&1.serial == serial)),
      do: {:error, :duplicate_serial},
      else: :ok
  end

  defp serial_param(serial) when is_binary(serial) do
    case String.trim(serial) do
      "" -> {:error, :bad_request}
      trimmed -> {:ok, trimmed}
    end
  end

  defp serial_param(_serial), do: {:error, :bad_request}

  defp aggregation_body(conn, id),
    do: conn |> org_id() |> Manufacturing.get_aggregation!(id) |> Serializer.aggregation()

  defp shipment_body(conn, id),
    do:
      conn
      |> org_id()
      |> Distributor.get_shipment!(id, "manufacturer")
      |> Serializer.shipment()

  defp load_sscc(conn, id) do
    with {:ok, id} <- parse_id(id) do
      fetch(fn -> Manufacturing.get_sscc_group!(org_id(conn), id) end)
    end
  end

  defp load_aggregation(conn, id) do
    with {:ok, id} <- parse_id(id) do
      fetch(fn -> Manufacturing.get_aggregation!(org_id(conn), id) end)
    end
  end

  defp load_shipment(conn, id) do
    with {:ok, id} <- parse_id(id) do
      fetch(fn -> Distributor.get_shipment!(org_id(conn), id, "manufacturer") end)
    end
  end

  defp status(status) when status in @statuses, do: status
  defp status(_status), do: nil

  defp date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _error -> nil
    end
  end

  defp date(_value), do: nil

  defp page(params) do
    {page, _per_page} = Params.page(params)
    page
  end

  # These lists use the web's fixed page sizes.
  defp meta(result) do
    %{
      page: result.page_number,
      per_page: result.page_size,
      total: result.total_entries,
      total_pages: result.total_pages
    }
  end
end
