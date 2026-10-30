defmodule ThamaniDawa.Reports do
  @moduledoc """
  Organization-wide analytics that don't belong to a single entity
  context: stock expiring across every site, committed spend per
  supplier, and per-site profitability. (Sales totals and transaction
  history live in `ThamaniDawa.Payments`; most-frequently-dispensed
  products reuse `ThamaniDawa.Dashboards.top_dispensed_products/3`.)
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.LabOrders.LabConsumableUsage
  alias ThamaniDawa.Payments
  alias ThamaniDawa.Payments.Payment
  alias ThamaniDawa.Payments.WalletEntry
  alias ThamaniDawa.Prescriptions.BatchDispense
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawa.Suppliers.Supplier

  @doc """
  Batches with stock remaining that expire within `within_days` (default
  30) of today, across every site in the organization, soonest first.
  """
  def expiring_batches(organization_id, within_days \\ 30) do
    cutoff = Date.add(Date.utc_today(), within_days)

    product_query = from p in Product, where: p.organization_id == ^organization_id
    site_query = from s in Site, where: s.organization_id == ^organization_id
    supplier_query = from s in Supplier, where: s.organization_id == ^organization_id

    Repo.all(
      from b in Batch,
        where: b.organization_id == ^organization_id,
        where: b.remaining_quantity > 0,
        where: b.expiry_date <= ^cutoff,
        order_by: [asc: b.expiry_date],
        preload: [product: ^product_query, site: ^site_query, supplier: ^supplier_query]
    )
  end

  @doc "Expiring batches for one site, using the same window as `expiring_batches/2`."
  def expiring_batches_for_site(organization_id, site_id, within_days \\ 30) do
    organization_id
    |> expiring_batches(within_days)
    |> Enum.filter(&(&1.site_id == site_id))
  end

  @doc """
  Per-site profitability: wallet revenue (`Payments.site_earnings_by_site/1`)
  minus the cost of goods actually dispensed/consumed at that site —
  pharmacy `prescription_batch_dispenses` plus lab `lab_consumable_usage`,
  each costed at its batch's `cost_per_unit`. Every site in the
  organization appears, even ones with no activity (at KES 0 all round),
  highest profit first.
  """
  def site_profitability(organization_id) do
    revenue = Payments.site_earnings_by_site(organization_id)
    cost_of_goods = cost_of_goods_by_site(organization_id)

    organization_id
    |> Sites.list_sites()
    |> Enum.map(fn site ->
      site_revenue = Map.get(revenue, site.id, Decimal.new(0))
      site_cost = Map.get(cost_of_goods, site.id, Decimal.new(0))

      %{
        site: site,
        revenue: site_revenue,
        cost_of_goods: site_cost,
        profit: Decimal.sub(site_revenue, site_cost)
      }
    end)
    |> Enum.sort_by(&Decimal.to_float(&1.profit), :desc)
  end

  @doc "Per-site profitability within an inclusive date range."
  def site_profitability(organization_id, %Date{} = from, %Date{} = to) do
    revenue = revenue_by_site(organization_id, from, to)
    cost_of_goods = cost_of_goods_by_site(organization_id, from, to)

    organization_id
    |> Sites.list_sites()
    |> Enum.map(fn site ->
      site_revenue = Map.get(revenue, site.id, Decimal.new(0))
      site_cost = Map.get(cost_of_goods, site.id, Decimal.new(0))

      %{
        site: site,
        revenue: site_revenue,
        cost_of_goods: site_cost,
        profit: Decimal.sub(site_revenue, site_cost)
      }
    end)
    |> Enum.sort_by(&Decimal.to_float(&1.profit), :desc)
  end

  @doc "Completed payment totals by method within a date range and optional site."
  def sales_by_payment_method(organization_id, site_id, %Date{} = from, %Date{} = to) do
    Payment
    |> where([p], p.organization_id == ^organization_id and p.status == :completed)
    |> where([p], p.paid_at >= ^to_start(from) and p.paid_at < ^to_end(to))
    |> maybe_filter_site(site_id)
    |> group_by([p], p.payment_type)
    |> select([p], {p.payment_type, sum(p.amount)})
    |> order_by([p], desc: sum(p.amount))
    |> Repo.all()
  end

  defp revenue_by_site(organization_id, from, to) do
    from(w in WalletEntry,
      where: w.organization_id == ^organization_id,
      where: w.inserted_at >= ^to_start(from) and w.inserted_at < ^to_end(to),
      group_by: w.site_id,
      select: {w.site_id, sum(w.amount)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp cost_of_goods_by_site(organization_id) do
    pharmacy =
      Repo.all(
        from d in BatchDispense,
          join: b in Batch,
          on: b.id == d.batch_id,
          where: d.organization_id == ^organization_id,
          group_by: b.site_id,
          select: {b.site_id, sum(d.quantity * coalesce(b.cost_per_unit, 0))}
      )

    lab =
      Repo.all(
        from u in LabConsumableUsage,
          join: b in Batch,
          on: b.id == u.batch_id,
          where: u.organization_id == ^organization_id,
          group_by: b.site_id,
          select: {b.site_id, sum(u.quantity * coalesce(b.cost_per_unit, 0))}
      )

    Map.merge(Map.new(pharmacy), Map.new(lab), fn _site_id, a, b -> Decimal.add(a, b) end)
  end

  defp cost_of_goods_by_site(organization_id, from, to) do
    pharmacy =
      Repo.all(
        from d in BatchDispense,
          join: b in Batch,
          on: b.id == d.batch_id,
          where: d.organization_id == ^organization_id,
          where: d.dispensed_at >= ^to_start(from) and d.dispensed_at < ^to_end(to),
          group_by: b.site_id,
          select: {b.site_id, sum(d.quantity * coalesce(b.cost_per_unit, 0))}
      )

    lab =
      Repo.all(
        from u in LabConsumableUsage,
          join: b in Batch,
          on: b.id == u.batch_id,
          where: u.organization_id == ^organization_id,
          where: u.used_at >= ^to_start(from) and u.used_at < ^to_end(to),
          group_by: b.site_id,
          select: {b.site_id, sum(u.quantity * coalesce(b.cost_per_unit, 0))}
      )

    Map.merge(Map.new(pharmacy), Map.new(lab), fn _site_id, a, b -> Decimal.add(a, b) end)
  end

  defp maybe_filter_site(query, nil), do: query
  defp maybe_filter_site(query, site_id), do: where(query, [row], row.site_id == ^site_id)

  defp to_start(date), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
  defp to_end(date), do: date |> Date.add(1) |> to_start()
end
