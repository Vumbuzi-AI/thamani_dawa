defmodule ThamaniDawa.StockAlerts do
  @moduledoc """
  Stock alert calculations shared by the pharmacy dashboard and the
  organization stock page: which products are out of stock, which sit at or
  below their reorder level, which batches are near expiry, and what it would
  cost to bring the low ones back up to their reorder level.

  Everything here works on an already-fetched list of batches, so callers stay
  in control of site scoping — a batch list is narrowed to the sites a user
  may see *before* it is handed to these functions.
  """

  @doc """
  Splits products into `{out_of_stock, low_stock}` lists of
  `{product, total_remaining}` pairs.

  Only products with a reorder level are considered; totals are the sum of
  `remaining_quantity` across the given batches.
  """
  def stock_alerts(batches, products_by_id) do
    batches
    |> Enum.group_by(& &1.product_id)
    |> Enum.map(fn {product_id, product_batches} ->
      {products_by_id[product_id], Enum.sum(Enum.map(product_batches, & &1.remaining_quantity))}
    end)
    |> Enum.filter(fn {product, _total} -> product && product.reorder_level end)
    |> split_stock_alerts()
  end

  @doc "Batches with stock left that expire within `days` days, soonest first."
  def near_expiry(batches, days \\ 30) do
    today = Date.utc_today()

    batches
    |> Enum.filter(fn batch ->
      batch.remaining_quantity > 0 &&
        Date.diff(batch.expiry_date, today) in 0..days
    end)
    |> Enum.sort_by(& &1.expiry_date, Date)
  end

  @doc """
  Estimated cost to bring the given low-stock products back up to their
  reorder level, priced from the average cost per unit of the batches on hand.
  """
  def low_stock_replenishment_value(low_stock, batches) do
    Enum.reduce(low_stock, 0.0, fn {product, remaining}, total ->
      target_quantity = max(product.reorder_level - remaining, 0)

      {cost_total, quantity_total} =
        batches
        |> Enum.filter(&(&1.product_id == product.id and &1.quantity > 0 and &1.cost_per_unit))
        |> Enum.reduce({0.0, 0}, fn batch, {cost, quantity} ->
          {cost + Decimal.to_float(batch.cost_per_unit) * batch.quantity,
           quantity + batch.quantity}
        end)

      if quantity_total > 0 do
        total + target_quantity * cost_total / quantity_total
      else
        total
      end
    end)
  end

  defp split_stock_alerts(totals) do
    {out, low} =
      Enum.reduce(totals, {[], []}, fn {product, total} = entry, {out, low} ->
        cond do
          total <= 0 -> {[entry | out], low}
          total <= product.reorder_level -> {out, [entry | low]}
          true -> {out, low}
        end
      end)

    {Enum.reverse(out), Enum.reverse(low)}
  end
end
