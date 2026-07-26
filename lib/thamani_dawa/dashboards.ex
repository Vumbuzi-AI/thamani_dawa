defmodule ThamaniDawa.Dashboards do
  @moduledoc """
  Read-only aggregation queries for the admin, pharmacy, and lab dashboards.
  Kept separate from the CRUD contexts (`Payments`, `Prescriptions`,
  `LabOrders`, ...) since these are reporting queries, not entity lifecycle
  operations.

  Every function takes an `organization_id` and an optional `site_id`
  (`nil` means network-wide, matching `Scope.current_site_id` /
  `SiteScoping`'s convention).
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.LabOrders.LabOrder
  alias ThamaniDawa.Patients.Patient
  alias ThamaniDawa.PatientVisits.PatientVisit
  alias ThamaniDawa.Payments.WalletEntry
  alias ThamaniDawa.Prescriptions.BatchDispense
  alias ThamaniDawa.Prescriptions.Prescription
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.Repo

  @doc "Named date ranges for the admin dashboard's range filter, in display order."
  def ranges do
    [
      {"this_month", "This Month"},
      {"last_month", "Last Month"},
      {"last_30_days", "Last 30 Days"},
      {"this_year", "This Year"},
      {"all_time", "All Time"}
    ]
  end

  @doc "Resolves a range key (see `ranges/0`) to a `{from, to}` Date pair. `to` is always today."
  def range_dates(key) do
    today = Date.utc_today()
    last_day_of_last_month = today |> Date.beginning_of_month() |> Date.add(-1)

    case key do
      "this_month" -> {Date.beginning_of_month(today), today}
      "last_month" -> {Date.beginning_of_month(last_day_of_last_month), last_day_of_last_month}
      "last_30_days" -> {Date.add(today, -29), today}
      "this_year" -> {%{today | month: 1, day: 1}, today}
      "all_time" -> {~D[2000-01-01], today}
      _ -> range_dates("this_month")
    end
  end

  @doc """
  Core admin/org stat-tile numbers for the given window and optional site.
  """
  def admin_stats(organization_id, site_id, {from, to}) do
    %{
      total_patients: count(Patient, organization_id),
      patient_visits: count_visits(organization_id, site_id, from, to),
      revenue_collected: sum_wallet_entries(organization_id, site_id, from, to),
      active_staff: count_active_users(organization_id),
      prescriptions: count_prescriptions(organization_id, site_id, from, to),
      lab_tests_done: count_completed_lab_orders(organization_id, site_id, from, to),
      pending_prescriptions: count_pending_prescriptions(organization_id, site_id),
      pending_lab_orders: count_pending_lab_orders(organization_id, site_id)
    }
  end

  @doc "Daily wallet revenue between `from` and `to` (inclusive), zero-filled for gap days."
  def daily_revenue(organization_id, site_id, from, to) do
    rows =
      wallet_entries_query(organization_id, site_id)
      |> where([w], w.inserted_at >= ^to_start(from) and w.inserted_at < ^to_end(to))
      |> group_by([w], fragment("date_trunc('day', ?)", w.inserted_at))
      |> select([w], {fragment("date_trunc('day', ?)", w.inserted_at), sum(w.amount)})
      |> Repo.all()
      |> Map.new(fn {date, amount} -> {to_date(date), decimal_to_float(amount)} end)

    for date <- Date.range(from, to), do: {date, Map.get(rows, date, 0.0)}
  end

  @doc "Total wallet revenue per month for the trailing `months` months (default 12)."
  def monthly_revenue(organization_id, site_id, months \\ 12) do
    today = Date.utc_today()
    start_month = Date.beginning_of_month(today) |> shift_months(-(months - 1))

    rows =
      wallet_entries_query(organization_id, site_id)
      |> where([w], w.inserted_at >= ^to_start(start_month))
      |> group_by([w], fragment("date_trunc('month', ?)", w.inserted_at))
      |> select([w], {fragment("date_trunc('month', ?)", w.inserted_at), sum(w.amount)})
      |> Repo.all()
      |> Map.new(fn {date, amount} ->
        {%{to_date(date) | day: 1}, decimal_to_float(amount)}
      end)

    for i <- (months - 1)..0 do
      month = shift_months(Date.beginning_of_month(today), -i)
      {month, Map.get(rows, month, 0.0)}
    end
  end

  @doc "Stat-tile numbers for the pharmacy dashboard (this-month window)."
  def pharmacy_stats(organization_id, site_id) do
    {from, to} = range_dates("this_month")

    %{
      revenue_this_month: sum_wallet_entries(organization_id, site_id, from, to)
    }
  end

  @doc "Prescriptions dispensed per day over the last `days` days (default 30), zero-filled."
  def dispensed_by_day(organization_id, site_id, days \\ 30) do
    to = Date.utc_today()
    from = Date.add(to, -(days - 1))

    rows =
      from(d in BatchDispense,
        join: b in Batch,
        on: b.id == d.batch_id,
        where: d.organization_id == ^organization_id,
        where: d.dispensed_at >= ^to_start(from) and d.dispensed_at < ^to_end(to)
      )
      |> filter_by_site(site_id, dynamic([_d, b], b.site_id == ^site_id))
      |> group_by([d], fragment("date_trunc('day', ?)", d.dispensed_at))
      |> select([d], {fragment("date_trunc('day', ?)", d.dispensed_at), sum(d.quantity)})
      |> Repo.all()
      |> Map.new(fn {date, qty} -> {to_date(date), qty || 0} end)

    for date <- Date.range(from, to), do: {date, Map.get(rows, date, 0)}
  end

  @doc "Top `limit` (default 5) dispensed products this month by quantity."
  def top_dispensed_products(organization_id, site_id, limit \\ 5) do
    {from, to} = range_dates("this_month")

    from(d in BatchDispense,
      join: b in Batch,
      on: b.id == d.batch_id,
      join: p in Product,
      on: p.id == b.product_id,
      where: d.organization_id == ^organization_id,
      where: d.dispensed_at >= ^to_start(from) and d.dispensed_at < ^to_end(to)
    )
    |> filter_by_site(site_id, dynamic([_d, b, _p], b.site_id == ^site_id))
    |> group_by([_d, _b, p], [p.id, p.generic_name, p.brand_name])
    |> select([d, _b, p], {p.generic_name, p.brand_name, sum(d.quantity)})
    |> order_by([d], desc: sum(d.quantity))
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(fn {generic_name, brand_name, qty} -> {generic_name || brand_name || "Unnamed", qty} end)
  end

  @doc "Stat-tile numbers for the lab dashboard (this-month window)."
  def lab_stats(organization_id, site_id) do
    {from, to} = range_dates("this_month")

    %{
      revenue_this_month: sum_wallet_entries(organization_id, site_id, from, to)
    }
  end

  @doc "Lab orders created per day over the last `days` days (default 30), zero-filled."
  def lab_orders_by_day(organization_id, site_id, days \\ 30) do
    to = Date.utc_today()
    from = Date.add(to, -(days - 1))

    rows =
      from(o in LabOrder,
        where: o.organization_id == ^organization_id,
        where: o.inserted_at >= ^to_start(from) and o.inserted_at < ^to_end(to)
      )
      |> filter_by_site(site_id, dynamic([o], o.site_id == ^site_id))
      |> group_by([o], fragment("date_trunc('day', ?)", o.inserted_at))
      |> select([o], {fragment("date_trunc('day', ?)", o.inserted_at), count(o.id)})
      |> Repo.all()
      |> Map.new(fn {date, n} -> {to_date(date), n} end)

    for date <- Date.range(from, to), do: {date, Map.get(rows, date, 0)}
  end

  @doc "Lab order counts grouped by status, in `LabOrder.statuses/0` order."
  def lab_orders_by_status(organization_id, site_id) do
    counts =
      from(o in LabOrder, where: o.organization_id == ^organization_id)
      |> filter_by_site(site_id, dynamic([o], o.site_id == ^site_id))
      |> group_by([o], o.status)
      |> select([o], {o.status, count(o.id)})
      |> Repo.all()
      |> Map.new()

    for status <- LabOrder.statuses(), do: {status, Map.get(counts, status, 0)}
  end

  # -- shared helpers ---------------------------------------------------

  defp count(schema, organization_id) do
    Repo.aggregate(from(s in schema, where: s.organization_id == ^organization_id), :count)
  end

  defp count_active_users(organization_id) do
    Repo.aggregate(
      from(u in User, where: u.organization_id == ^organization_id and u.is_active == true),
      :count
    )
  end

  defp count_visits(organization_id, site_id, from, to) do
    from(v in PatientVisit,
      where: v.organization_id == ^organization_id,
      where: v.inserted_at >= ^to_start(from) and v.inserted_at < ^to_end(to)
    )
    |> filter_by_site(site_id, dynamic([v], v.site_id == ^site_id))
    |> Repo.aggregate(:count)
  end

  defp count_prescriptions(organization_id, site_id, from, to) do
    from(p in Prescription,
      join: v in PatientVisit,
      on: v.id == p.patient_visit_id,
      where: p.organization_id == ^organization_id,
      where: p.inserted_at >= ^to_start(from) and p.inserted_at < ^to_end(to)
    )
    |> filter_by_site(site_id, dynamic([_p, v], v.site_id == ^site_id))
    |> Repo.aggregate(:count)
  end

  defp count_pending_prescriptions(organization_id, site_id) do
    from(p in Prescription,
      join: v in PatientVisit,
      on: v.id == p.patient_visit_id,
      where: p.organization_id == ^organization_id,
      where: p.status in [:pending, :partially_dispensed]
    )
    |> filter_by_site(site_id, dynamic([_p, v], v.site_id == ^site_id))
    |> Repo.aggregate(:count)
  end

  defp count_pending_lab_orders(organization_id, site_id) do
    from(o in LabOrder,
      where: o.organization_id == ^organization_id,
      where: o.status in [:pending, :in_progress]
    )
    |> filter_by_site(site_id, dynamic([o], o.site_id == ^site_id))
    |> Repo.aggregate(:count)
  end

  defp count_completed_lab_orders(organization_id, site_id, from, to) do
    from(o in LabOrder,
      where: o.organization_id == ^organization_id,
      where: o.status == :completed,
      where: o.inserted_at >= ^to_start(from) and o.inserted_at < ^to_end(to)
    )
    |> filter_by_site(site_id, dynamic([o], o.site_id == ^site_id))
    |> Repo.aggregate(:count)
  end

  defp sum_wallet_entries(organization_id, site_id, from, to) do
    wallet_entries_query(organization_id, site_id)
    |> where([w], w.inserted_at >= ^to_start(from) and w.inserted_at < ^to_end(to))
    |> select([w], sum(w.amount))
    |> Repo.one()
    |> decimal_to_float()
  end

  defp wallet_entries_query(organization_id, site_id) do
    from(w in WalletEntry, where: w.organization_id == ^organization_id)
    |> filter_by_site(site_id, dynamic([w], w.site_id == ^site_id))
  end

  defp filter_by_site(query, nil, _dyn), do: query
  defp filter_by_site(query, _site_id, dyn), do: where(query, ^dyn)

  defp to_start(date), do: DateTime.new!(date, ~T[00:00:00])
  defp to_end(date), do: date |> Date.add(1) |> to_start()

  # `date_trunc` fragments decode as NaiveDateTime when the underlying
  # column is a Postgres `timestamp` (no time zone) — which is what
  # `timestamps(type: :utc_datetime)` actually creates — rather than DateTime.
  defp to_date(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_date(ndt)
  defp to_date(%DateTime{} = dt), do: DateTime.to_date(dt)

  defp shift_months(%Date{year: year, month: month} = date, offset) do
    total = year * 12 + (month - 1) + offset
    %{date | year: div(total, 12), month: rem(total, 12) + 1}
  end

  defp decimal_to_float(nil), do: 0.0
  defp decimal_to_float(%Decimal{} = d), do: Decimal.to_float(d)
end
