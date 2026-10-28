defmodule ThamaniDawa.StockTakes do
  @moduledoc """
  Organization- and site-scoped stock take sessions. A session collects one
  auditable physical count per included batch, then finalises by setting each
  batch's `remaining_quantity` to the counted value and recording who finalised
  and when. Finalization is protected against concurrent double-calls via a
  `FOR UPDATE` row-level lock on the session.

  When a stock take is created, a count row is automatically materialised for
  every active (received and approved) batch at the site via
  `populate_items_for_site/3`. That function is idempotent — calling it again
  only adds rows for batches not yet represented, so it is safe to call on
  every page mount.
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.Repo
  alias ThamaniDawa.StockTakes.StockTake
  alias ThamaniDawa.StockTakes.StockTakeItem

  @doc "Lists all stock takes for an organization."
  def list_stock_takes(organization_id) do
    Repo.all(
      from st in StockTake,
        where: st.organization_id == ^organization_id,
        order_by: [desc: st.inserted_at]
    )
  end

  @doc "Lists all stock takes for an organization with pagination."
  def list_stock_takes_paginated(organization_id, page \\ 1) do
    from(st in StockTake,
      where: st.organization_id == ^organization_id,
      order_by: [desc: st.inserted_at]
    )
    |> Repo.paginate(page: page)
  end

  @doc "Lists stock takes for a specific site within an organization."
  def list_stock_takes_for_site(organization_id, site_id) do
    Repo.all(
      from st in StockTake,
        where: st.organization_id == ^organization_id,
        where: st.site_id == ^site_id,
        order_by: [desc: st.inserted_at]
    )
  end

  @doc """
  Gets a single stock take scoped to an organization, preloaded with items and
  each item's batch. Raises if not found.
  """
  def get_stock_take!(organization_id, id) do
    batch_query = from b in Batch, where: b.organization_id == ^organization_id

    StockTake
    |> Repo.get_by!(id: id, organization_id: organization_id)
    |> Repo.preload(items: {from(i in StockTakeItem, order_by: i.id), batch: batch_query})
  end

  @doc "Returns a changeset for building or validating a stock take form."
  def change_stock_take(%StockTake{} = stock_take, attrs \\ %{}) do
    StockTake.changeset(stock_take, attrs)
  end

  @doc """
  Creates a new draft stock take for a site and immediately populates a count
  row for every active batch at that site. `attrs` must include `site_id` and
  `started_by_id`; `notes` is optional.
  """
  def create_stock_take(organization_id, attrs) when is_integer(organization_id) do
    Repo.transaction(fn ->
      with {:ok, stock_take} <-
             %StockTake{}
             |> StockTake.changeset(attrs)
             |> Ecto.Changeset.put_change(:organization_id, organization_id)
             |> Repo.audited_insert(),
           results <- populate_items_for_site(stock_take, organization_id, stock_take.site_id),
           :ok <- ensure_items_inserted(results) do
        stock_take
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp ensure_items_inserted(results) do
    case Enum.find(results, &match?({:error, _reason}, &1)) do
      nil -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Idempotently materialises a `StockTakeItem` for every active (received and
  approved, with stock remaining) batch at `site_id`. Batches that already
  have an item in this session are skipped. The snapshot `expected_quantity`
  is the batch's current `remaining_quantity` at the moment the row is
  inserted.

  Returns a list of `{:ok, item}` / `{:error, changeset}` tuples — one per
  batch that needed a new row.
  """
  def populate_items_for_site(%StockTake{} = stock_take, organization_id, site_id) do
    active_batches = Batches.list_active_batches_for_site(organization_id, site_id)

    existing_batch_ids =
      MapSet.new(
        Repo.all(
          from i in StockTakeItem,
            where: i.stock_take_id == ^stock_take.id,
            select: i.batch_id
        )
      )

    active_batches
    |> Enum.reject(&MapSet.member?(existing_batch_ids, &1.id))
    |> Enum.map(&insert_item(stock_take, &1))
  end

  defp insert_item(%StockTake{} = stock_take, %Batch{} = batch) do
    %StockTakeItem{}
    |> StockTakeItem.create_changeset(%{
      stock_take_id: stock_take.id,
      batch_id: batch.id,
      organization_id: stock_take.organization_id,
      expected_quantity: batch.remaining_quantity
    })
    |> Repo.audited_insert()
  end

  @doc """
  Adds a batch to a draft stock take, snapshotting the current
  `remaining_quantity` as `expected_quantity`. Returns
  `{:error, :already_finalized}` if the session is no longer a draft.
  """
  def add_item(%StockTake{status: :finalized}, _batch), do: {:error, :already_finalized}

  def add_item(%StockTake{} = stock_take, %Batch{} = batch) do
    %StockTakeItem{}
    |> StockTakeItem.create_changeset(%{
      stock_take_id: stock_take.id,
      batch_id: batch.id,
      organization_id: stock_take.organization_id,
      expected_quantity: batch.remaining_quantity
    })
    |> Repo.audited_insert()
  end

  @doc """
  Records the physical count for a stock take item, computing and storing the
  variance. Returns `{:error, :already_finalized}` if the parent session is
  finalized.
  """
  def record_count(%StockTakeItem{} = item, counted_quantity, user_id, attrs \\ %{}) do
    parent = Repo.get!(StockTake, item.stock_take_id)

    if parent.status == :finalized do
      {:error, :already_finalized}
    else
      item
      |> StockTakeItem.count_changeset(
        Map.merge(attrs, %{
          "counted_quantity" => counted_quantity,
          "counted_by_id" => user_id,
          "counted_at" => DateTime.utc_now()
        })
      )
      |> Repo.audited_update()
    end
  end

  @doc """
  Finalizes a draft stock take in a single transaction:

  1. Locks the stock take row `FOR UPDATE` to prevent concurrent finalization.
  2. Verifies the session is still a draft.
  3. Ensures every item has a recorded count.
  4. Sets each batch's `remaining_quantity` to the counted value (physical
     count wins).
  5. Marks the session as finalized, recording `finalized_by_id` and
     `finalized_at`.

  Returns `{:error, :already_finalized}` or `{:error, :uncounted_items}` on
  the relevant guard failures.
  """
  def finalize_stock_take(%StockTake{} = stock_take, user_id) do
    Repo.transaction(fn ->
      locked =
        Repo.one!(
          from st in StockTake,
            where: st.id == ^stock_take.id,
            where: st.organization_id == ^stock_take.organization_id,
            lock: "FOR UPDATE"
        )

      if locked.status == :finalized do
        Repo.rollback(:already_finalized)
      end

      items =
        Repo.all(
          from i in StockTakeItem,
            where: i.stock_take_id == ^stock_take.id,
            where: i.organization_id == ^stock_take.organization_id
        )

      if Enum.any?(items, &is_nil(&1.counted_quantity)) do
        Repo.rollback(:uncounted_items)
      end

      Enum.each(items, fn item ->
        Batch
        |> where([b], b.id == ^item.batch_id)
        |> lock("FOR UPDATE")
        |> Repo.one!()
        |> Ecto.Changeset.change(remaining_quantity: item.counted_quantity)
        |> Repo.audited_update!()
      end)

      locked
      |> StockTake.finalize_changeset(%{
        finalized_by_id: user_id,
        finalized_at: DateTime.utc_now()
      })
      |> Repo.audited_update!()
    end)
  end
end
