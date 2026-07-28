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
  alias ThamaniDawa.Sites.Site

  @doc "Named date ranges for the admin dashboard's range filter, in display order."
  def ranges do
    [
      {"today", "Today"},
      {"this_week", "This Week"},
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
      "today" -> {today, today}
      "this_week" -> {Date.beginning_of_week(today), today}
      "this_month" -> {Date.beginning_of_month(today), today}
      "last_month" -> {Date.beginning_of_month(last_day_of_last_month), last_day_of_last_month}
      "last_30_days" -> {Date.add(today, -29), today}
      "this_year" -> {%{today | month: 1, day: 1}, today}
      "all_time" -> {~D[2000-01-01], today}
      _ -> range_dates("this_month")
    end
  end

  @doc """
  Resolves an admin-supplied `{from, to}` window for a custom date-range
  filter (see `ThamaniDawaWeb.SiteLive.Show`). Swaps the pair if `from` is
  after `to`, so the caller doesn't have to validate ordering.
  """
  def custom_range_dates(%Date{} = from, %Date{} = to) do
    case Date.compare(from, to) do
      :gt -> {to, from}
      _ -> {from, to}
    end
  end

  @doc """
  Core admin/org stat-tile numbers for the given window, optional site, and optional search query.
  """
  def admin_stats(organization_id, site_id, {from, to}, search_query \\ nil) do
    term = String.trim(search_query || "")

    if term == "" do
      default_admin_stats(organization_id, site_id, {from, to})
    else
      search_filtered_admin_stats(organization_id, site_id, {from, to}, "%#{term}%")
    end
  end

  defp default_admin_stats(organization_id, site_id, {from, to}) do
    %{
      total_patients: count_patients(organization_id, site_id),
      patient_visits: count_visits(organization_id, site_id, from, to),
      revenue_collected: sum_wallet_entries(organization_id, site_id, from, to),
      active_staff: count_active_users(organization_id, site_id),
      prescriptions: count_prescriptions(organization_id, site_id, from, to),
      lab_tests_done: count_completed_lab_orders(organization_id, site_id, from, to),
      pending_prescriptions: count_pending_prescriptions(organization_id, site_id),
      pending_lab_orders: count_pending_lab_orders(organization_id, site_id)
    }
  end

  defp search_filtered_admin_stats(organization_id, site_id, {from, to}, pattern) do
    %{
      total_patients: count_search_patients(organization_id, site_id, pattern),
      patient_visits: count_search_visits(organization_id, site_id, from, to, pattern),
      revenue_collected: sum_search_revenue(organization_id, site_id, from, to, pattern),
      active_staff: count_search_staff(organization_id, site_id, pattern),
      prescriptions: count_search_prescriptions(organization_id, site_id, from, to, pattern),
      lab_tests_done: count_search_lab_tests(organization_id, site_id, from, to, pattern),
      pending_prescriptions:
        count_search_pending_prescriptions(organization_id, site_id, pattern),
      pending_lab_orders: count_search_pending_lab_orders(organization_id, site_id, pattern)
    }
  end

  defp count_search_patients(organization_id, nil, pattern) do
    Repo.aggregate(
      from(p in Patient,
        where: p.organization_id == ^organization_id,
        where:
          ilike(p.full_name, ^pattern) or ilike(p.phone, ^pattern) or
            ilike(p.national_id, ^pattern)
      ),
      :count
    )
  end

  defp count_search_patients(organization_id, site_id, pattern) do
    from(p in Patient,
      join: v in PatientVisit,
      on: v.patient_id == p.id,
      where: p.organization_id == ^organization_id and v.site_id == ^site_id,
      where:
        ilike(p.full_name, ^pattern) or ilike(p.phone, ^pattern) or
          ilike(p.national_id, ^pattern),
      select: count(p.id, :distinct)
    )
    |> Repo.one() || 0
  end

  defp count_search_visits(organization_id, site_id, from, to, pattern) do
    from(v in PatientVisit,
      join: p in Patient,
      on: p.id == v.patient_id,
      join: s in Site,
      on: s.id == v.site_id,
      where: v.organization_id == ^organization_id,
      where: v.inserted_at >= ^to_start(from) and v.inserted_at < ^to_end(to),
      where: ilike(p.full_name, ^pattern) or ilike(p.phone, ^pattern) or ilike(s.name, ^pattern)
    )
    |> filter_by_site(site_id, dynamic([v, _p, _s], v.site_id == ^site_id))
    |> Repo.aggregate(:count)
  end

  defp count_search_staff(organization_id, nil, pattern) do
    Repo.aggregate(
      from(u in User,
        where: u.organization_id == ^organization_id and u.is_active == true,
        where: ilike(u.name, ^pattern) or ilike(u.email, ^pattern)
      ),
      :count
    )
  end

  defp count_search_staff(organization_id, site_id, pattern) do
    from(u in User,
      join: us in ThamaniDawa.Accounts.UserSite,
      on: us.user_id == u.id,
      where:
        u.organization_id == ^organization_id and u.is_active == true and us.site_id == ^site_id,
      where: ilike(u.name, ^pattern) or ilike(u.email, ^pattern)
    )
    |> Repo.aggregate(:count)
  end

  defp count_search_prescriptions(organization_id, site_id, from, to, pattern) do
    from(p in Prescription,
      join: v in PatientVisit,
      on: v.id == p.patient_visit_id,
      join: pat in Patient,
      on: pat.id == v.patient_id,
      where: p.organization_id == ^organization_id,
      where: p.inserted_at >= ^to_start(from) and p.inserted_at < ^to_end(to),
      where: ilike(pat.full_name, ^pattern) or ilike(pat.phone, ^pattern)
    )
    |> filter_by_site(site_id, dynamic([_p, v, _pat], v.site_id == ^site_id))
    |> Repo.aggregate(:count)
  end

  defp count_search_lab_tests(organization_id, site_id, from, to, pattern) do
    from(o in LabOrder,
      join: v in PatientVisit,
      on: v.id == o.patient_visit_id,
      join: pat in Patient,
      on: pat.id == v.patient_id,
      where: o.organization_id == ^organization_id,
      where: o.status == :completed,
      where: o.inserted_at >= ^to_start(from) and o.inserted_at < ^to_end(to),
      where: ilike(pat.full_name, ^pattern) or ilike(pat.phone, ^pattern)
    )
    |> filter_by_site(site_id, dynamic([o, _v, _pat], o.site_id == ^site_id))
    |> Repo.aggregate(:count)
  end

  defp count_search_pending_prescriptions(organization_id, site_id, pattern) do
    from(p in Prescription,
      join: v in PatientVisit,
      on: v.id == p.patient_visit_id,
      join: pat in Patient,
      on: pat.id == v.patient_id,
      where: p.organization_id == ^organization_id,
      where: p.status in [:pending, :partially_dispensed],
      where: ilike(pat.full_name, ^pattern) or ilike(pat.phone, ^pattern)
    )
    |> filter_by_site(site_id, dynamic([_p, v, _pat], v.site_id == ^site_id))
    |> Repo.aggregate(:count)
  end

  defp count_search_pending_lab_orders(organization_id, site_id, pattern) do
    from(o in LabOrder,
      join: v in PatientVisit,
      on: v.id == o.patient_visit_id,
      join: pat in Patient,
      on: pat.id == v.patient_id,
      where: o.organization_id == ^organization_id,
      where: o.status in [:pending, :in_progress],
      where: ilike(pat.full_name, ^pattern) or ilike(pat.phone, ^pattern)
    )
    |> filter_by_site(site_id, dynamic([o, _v, _pat], o.site_id == ^site_id))
    |> Repo.aggregate(:count)
  end

  defp sum_search_revenue(organization_id, site_id, from, to, pattern) do
    from(w in WalletEntry,
      join: pay in ThamaniDawa.Payments.Payment,
      on: pay.id == w.payment_id,
      left_join: rx in Prescription,
      on: rx.id == pay.prescription_id,
      left_join: lab in LabOrder,
      on: lab.id == pay.lab_order_id,
      left_join: v1 in PatientVisit,
      on: v1.id == rx.patient_visit_id,
      left_join: v2 in PatientVisit,
      on: v2.id == lab.patient_visit_id,
      left_join: p1 in Patient,
      on: p1.id == v1.patient_id,
      left_join: p2 in Patient,
      on: p2.id == v2.patient_id,
      where: w.organization_id == ^organization_id,
      where: w.inserted_at >= ^to_start(from) and w.inserted_at < ^to_end(to),
      where:
        ilike(p1.full_name, ^pattern) or ilike(p2.full_name, ^pattern) or
          ilike(p1.phone, ^pattern) or ilike(p2.phone, ^pattern)
    )
    |> filter_by_site(
      site_id,
      dynamic([w, _pay, _rx, _lab, _v1, _v2, _p1, _p2], w.site_id == ^site_id)
    )
    |> select([w, _pay, _rx, _lab, _v1, _v2, _p1, _p2], sum(w.amount))
    |> Repo.one()
    |> decimal_to_float()
  end

  @doc """
  Performs search across patients, sites, staff, and visits for the admin dashboard.
  """
  def search_admin_dashboard(organization_id, search_query, {from, to}, site_id \\ nil) do
    term = String.trim(search_query || "")

    if term == "" do
      %{patients: [], sites: [], staff: [], visits: []}
    else
      pattern = "%#{term}%"

      %{
        patients: search_patients_list(organization_id, pattern, site_id),
        sites: search_sites_list(organization_id, pattern),
        staff: search_staff_list(organization_id, pattern, site_id),
        visits: search_visits_list(organization_id, site_id, {from, to}, pattern)
      }
    end
  end

  defp search_patients_list(organization_id, pattern, site_id) do
    base =
      from(p in Patient,
        where: p.organization_id == ^organization_id,
        where:
          ilike(p.full_name, ^pattern) or ilike(p.phone, ^pattern) or
            ilike(p.national_id, ^pattern),
        order_by: [desc: p.inserted_at],
        limit: 5
      )

    query =
      if site_id do
        from(p in base,
          join: v in PatientVisit,
          on: v.patient_id == p.id and v.site_id == ^site_id,
          distinct: true
        )
      else
        base
      end

    Repo.all(query)
  end

  defp search_sites_list(organization_id, pattern) do
    from(s in Site,
      where: s.organization_id == ^organization_id,
      where: ilike(s.name, ^pattern) or ilike(s.gln, ^pattern) or ilike(s.address, ^pattern),
      limit: 5
    )
    |> Repo.all()
  end

  defp search_staff_list(organization_id, pattern, site_id) do
    base =
      from(u in User,
        where: u.organization_id == ^organization_id,
        where: ilike(u.name, ^pattern) or ilike(u.email, ^pattern),
        limit: 5
      )

    query =
      if site_id do
        from(u in base,
          join: us in ThamaniDawa.Accounts.UserSite,
          on: us.user_id == u.id and us.site_id == ^site_id
        )
      else
        base
      end

    Repo.all(query)
  end

  defp search_visits_list(organization_id, site_id, {from, to}, pattern) do
    from(v in PatientVisit,
      join: p in Patient,
      on: p.id == v.patient_id,
      join: s in Site,
      on: s.id == v.site_id,
      where: v.organization_id == ^organization_id,
      where: v.inserted_at >= ^to_start(from) and v.inserted_at < ^to_end(to),
      where: ilike(p.full_name, ^pattern) or ilike(p.phone, ^pattern) or ilike(s.name, ^pattern),
      select: %{
        id: v.id,
        visit_type: v.visit_type,
        inserted_at: v.inserted_at,
        patient_name: p.full_name,
        site_name: s.name
      },
      order_by: [desc: v.inserted_at],
      limit: 5
    )
    |> filter_by_site(site_id, dynamic([v, _p, _s], v.site_id == ^site_id))
    |> Repo.all()
  end

  @doc """
  Site-scoped activity numbers for the `SiteLive.Show` stat cards: patient
  visits, prescriptions, and completed lab orders in the given window at a
  single site. Unlike `admin_stats/3` this skips the org-wide-only fields
  (`total_patients`, `revenue_collected`, `active_staff`, pending counts)
  that page doesn't show, so it only runs the three queries it needs.
  """
  def site_activity_stats(organization_id, site_id, {from, to}) do
    %{
      patient_visits: count_visits(organization_id, site_id, from, to),
      prescriptions: count_prescriptions(organization_id, site_id, from, to),
      lab_tests_done: count_completed_lab_orders(organization_id, site_id, from, to)
    }
  end

  @doc "Daily wallet revenue between `from` and `to` (inclusive), zero-filled for gap days."
  def daily_revenue(organization_id, site_id, from, to) do
    query = wallet_entries_query(organization_id, site_id)

    rows =
      query
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
    start_month = shift_months(Date.beginning_of_month(today), -(months - 1))
    query = wallet_entries_query(organization_id, site_id)

    rows =
      query
      |> where([w], w.inserted_at >= ^to_start(start_month))
      |> group_by([w], fragment("date_trunc('month', ?)", w.inserted_at))
      |> select([w], {fragment("date_trunc('month', ?)", w.inserted_at), sum(w.amount)})
      |> Repo.all()
      |> Map.new(fn {date, amount} ->
        {%{to_date(date) | day: 1}, decimal_to_float(amount)}
      end)

    for i <- (months - 1)..0//-1 do
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
    |> Enum.map(fn {generic_name, brand_name, qty} ->
      {generic_name || brand_name || "Unnamed", qty}
    end)
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

  defp count_patients(organization_id, nil) do
    count(Patient, organization_id)
  end

  defp count_patients(organization_id, site_id) do
    from(p in Patient,
      join: v in PatientVisit,
      on: v.patient_id == p.id,
      where: p.organization_id == ^organization_id and v.site_id == ^site_id,
      select: count(p.id, :distinct)
    )
    |> Repo.one() || 0
  end

  defp count_active_users(organization_id, nil) do
    Repo.aggregate(
      from(u in User, where: u.organization_id == ^organization_id and u.is_active == true),
      :count
    )
  end

  defp count_active_users(organization_id, site_id) do
    from(u in User,
      join: us in ThamaniDawa.Accounts.UserSite,
      on: us.user_id == u.id,
      where:
        u.organization_id == ^organization_id and u.is_active == true and us.site_id == ^site_id
    )
    |> Repo.aggregate(:count)
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
    query = wallet_entries_query(organization_id, site_id)

    query
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
