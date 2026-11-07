defmodule ThamaniDawa.Distributor.Reports do
  @moduledoc """
  Read-side helpers for the distributor shipment workflow: review warnings,
  grouped units, SSCC shipper labels, CSV export rows, and dashboard
  analytics. Shipments passed in are expected to be preloaded via
  `ThamaniDawa.Distributor.get_shipment!/2`.
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.Distributor.{SerialReservation, Shipment, ShipmentItem, Shipper}
  alias ThamaniDawa.Repo

  @doc """
  Warnings to surface while reviewing a shipment: unknown serials, data
  mismatches, expired units, unverified products, and serial conflicts with
  other shipments. Returns `[%{code:, count:, message:}]`.
  """
  def shipment_warnings(%Shipment{} = shipment) do
    items = items(shipment)
    today = Date.utc_today()

    [
      {:unknown_serial, Enum.count(items, &(&1.validation_status == "unknown_serial")),
       "unit(s) have a serial that isn't on any batch you've received"},
      {:data_mismatch, Enum.count(items, &(&1.validation_status == "data_mismatch")),
       "unit(s) have a batch number or dates that differ from the received batch"},
      {:expired,
       Enum.count(items, &(&1.expiry_date && Date.compare(&1.expiry_date, today) == :lt)),
       "unit(s) are past their expiry date"},
      {:unverified, Enum.count(items, &(&1.product_source == "unverified")),
       "unit(s) could not be verified against GS1 when scanned"},
      {:serial_conflict, conflict_count(shipment, items),
       "unit(s) are also in another submitted or approved shipment"}
    ]
    |> Enum.filter(fn {_code, count, _message} -> count > 0 end)
    |> Enum.map(fn {code, count, message} -> %{code: code, count: count, message: message} end)
  end

  defp conflict_count(_shipment, []), do: 0

  defp conflict_count(shipment, items) do
    keys = Enum.map(items, &{&1.gtin, &1.serial})
    gtins = keys |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    taken =
      from(r in SerialReservation,
        where: r.barcode in ^gtins and r.shipment_id != ^shipment.id,
        select: {r.barcode, r.serial}
      )
      |> Repo.all()
      |> MapSet.new()

    Enum.count(keys, &MapSet.member?(taken, &1))
  end

  @doc """
  Groups a shipment's units per shipper and product/batch/dates. Returns
  `[%{shipper:, groups: [%{id:, gtin:, batch:, production_date:,
  expiry_date:, product_name:, count:, items:}]}]`.
  """
  def item_groups(%Shipment{shippers: shippers}) do
    Enum.map(shippers, fn shipper ->
      groups =
        shipper.items
        |> Enum.group_by(&{&1.gtin, &1.batch, &1.production_date, &1.expiry_date})
        |> Enum.map(fn {{gtin, batch, production_date, expiry_date}, items} ->
          %{
            id: "shipper-#{shipper.id}-#{group_key(gtin, batch, production_date, expiry_date)}",
            gtin: gtin,
            batch: batch,
            production_date: production_date,
            expiry_date: expiry_date,
            product_name: Enum.find_value(items, & &1.product_name),
            count: length(items),
            items: Enum.sort_by(items, & &1.serial)
          }
        end)
        |> Enum.sort_by(&{&1.product_name || "", &1.batch || ""})

      %{shipper: shipper, groups: groups}
    end)
  end

  defp group_key(gtin, batch, production_date, expiry_date) do
    :sha256
    |> :crypto.hash("#{gtin}|#{batch}|#{production_date}|#{expiry_date}")
    |> Base.encode16(case: :lower)
    |> binary_part(0, 10)
  end

  @doc """
  One printable label per shipper of an approved shipment: SSCC, ship
  from/to (company, address, GLN), order details, and contents (a single
  GTIN/batch/dates combination, or mixed).
  """
  def shipper_labels(%Shipment{status: "approved", shippers: shippers} = shipment) do
    total = length(shippers)

    shippers
    |> Enum.filter(& &1.sscc)
    |> Enum.map(fn shipper ->
      %{
        id: shipper.id,
        sscc: shipper.sscc,
        name: shipper.name,
        position: "#{shipper.sequence} of #{total}",
        order_number: shipment.order_number,
        reference: shipment.reference,
        ship_from: party(shipment, :origin),
        ship_to: party(shipment, :destination),
        mixed: is_nil(shipper.gtin),
        gtin: shipper.gtin,
        batch: shipper.batch,
        production_date: shipper.production_date,
        expiry_date: shipper.expiry_date,
        product_name: shipper.product_name,
        unit_count: shipper.unit_count || length(shipper.items)
      }
    end)
  end

  def shipper_labels(_shipment), do: []

  defp party(shipment, :origin) do
    %{
      company: shipment.origin_company,
      address: shipment.origin_address,
      po_box: shipment.origin_po_box,
      gln: shipment.origin_gln
    }
  end

  defp party(shipment, :destination) do
    %{
      company: shipment.destination_company,
      address: shipment.destination_address,
      po_box: shipment.destination_po_box,
      gln: shipment.destination_gln
    }
  end

  @export_headers [
    "Reference",
    "Order number",
    "Status",
    "Shipper",
    "SSCC",
    "GTIN",
    "Product",
    "Batch",
    "Production date",
    "Expiry date",
    "Serial",
    "Validation status",
    "Scanned by",
    "Scanned at"
  ]

  @doc "CSV rows (header first) for every scanned unit in a shipment."
  def export_rows(%Shipment{} = shipment) do
    rows =
      for shipper <- shipment.shippers, item <- shipper.items do
        [
          shipment.reference,
          shipment.order_number,
          shipment.status,
          shipper.name,
          shipper.sscc,
          item.gtin,
          item.product_name,
          item.batch,
          item.production_date,
          item.expiry_date,
          item.serial,
          item.validation_status,
          item.scanned_by && item.scanned_by.name,
          item.scanned_at
        ]
      end

    [@export_headers | rows]
  end

  @doc """
  Encodes rows as CSV, neutralising spreadsheet formula injection: any cell
  starting with `=`, `+`, `-` or `@` is prefixed with `'`.
  """
  def to_csv(rows) do
    Enum.map_join(rows, "", fn row -> Enum.map_join(row, ",", &csv_cell/1) <> "\r\n" end)
  end

  defp csv_cell(value) do
    value = safe_cell(value)

    if String.contains?(value, [",", "\"", "\n", "\r"]),
      do: "\"" <> String.replace(value, "\"", "\"\"") <> "\"",
      else: value
  end

  @doc false
  def safe_cell(nil), do: ""
  def safe_cell(%Date{} = date), do: Date.to_iso8601(date)
  def safe_cell(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  def safe_cell(value) do
    value = to_string(value)
    if String.starts_with?(value, ["=", "+", "-", "@"]), do: "'" <> value, else: value
  end

  @doc """
  Shipment analytics for the distributor dashboard: status counts, units
  and SSCCs issued, this month's activity, recent shipments, and top
  shipped products.
  """
  def shipment_analytics(organization_id) do
    today = Date.utc_today()
    month_start = DateTime.new!(Date.beginning_of_month(today), ~T[00:00:00], "Etc/UTC")

    %{
      status_counts: status_counts(organization_id),
      units_shipped: units_shipped(organization_id),
      ssccs_issued:
        Repo.aggregate(
          from(sh in Shipper,
            where: sh.organization_id == ^organization_id and not is_nil(sh.sscc)
          ),
          :count,
          :id
        ),
      approved_this_month:
        Repo.aggregate(
          from(s in Shipment,
            where: s.organization_id == ^organization_id and s.status == "approved",
            where: s.approved_at >= ^month_start
          ),
          :count,
          :id
        ),
      recent_shipments: recent_shipments(organization_id),
      top_products: top_products(organization_id)
    }
  end

  defp status_counts(organization_id) do
    counts =
      Repo.all(
        from s in Shipment,
          where: s.organization_id == ^organization_id,
          group_by: s.status,
          select: {s.status, count(s.id)}
      )

    counts = Map.new(counts)
    Map.new(Shipment.statuses(), &{&1, Map.get(counts, &1, 0)})
  end

  defp units_shipped(organization_id) do
    Repo.aggregate(
      from(i in ShipmentItem,
        join: s in assoc(i, :shipment),
        where: i.organization_id == ^organization_id and s.status == "approved"
      ),
      :count,
      :id
    )
  end

  defp recent_shipments(organization_id) do
    Repo.all(
      from s in Shipment,
        where: s.organization_id == ^organization_id,
        order_by: [desc: s.updated_at, desc: s.id],
        limit: 5
    )
  end

  defp top_products(organization_id) do
    Repo.all(
      from i in ShipmentItem,
        join: s in assoc(i, :shipment),
        where: i.organization_id == ^organization_id and s.status == "approved",
        group_by: [i.gtin, i.product_name],
        select: %{gtin: i.gtin, product_name: i.product_name, units: count(i.id)},
        order_by: [desc: count(i.id)],
        limit: 5
    )
  end

  defp items(%Shipment{shippers: shippers}), do: Enum.flat_map(shippers, & &1.items)
end
