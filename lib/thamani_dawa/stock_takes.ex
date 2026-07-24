defmodule ThamaniDawa.StockTakes do
  @moduledoc """
  Physical stock-take sessions: staff at a site count what's actually on the shelf against
  what the system expects (`batches.remaining_quantity`), review variances, then finalize to
  correct the recorded quantities. Scoped to one site per stock take and pre-populated from
  every active batch there; finalizing flags — rather than overwrites — a batch that drifted
  mid-count.
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Batches
  alias ThamaniDawa.Repo
  alias ThamaniDawa.StockTakes.StockTake
  alias ThamaniDawa.StockTakes.StockTakeEntry

  @doc "Lists an organization's stock takes, most recently started first."
  def list_stock_takes(organization_id) do
    Repo.all(
      from st in StockTake,
        where: st.organization_id == ^organization_id,
        order_by: [desc: st.started_at]
    )
  end

  @doc """
  Gets a single stock take scoped to an organization, preloaded with its entries (ordered by
  id, i.e. count order). Raises if not found or not in this organization.
  """
  def get_stock_take!(organization_id, id) do
    StockTake
    |> Repo.get_by!(id: id, organization_id: organization_id)
    |> Repo.preload(entries: from(e in StockTakeEntry, order_by: e.id))
  end

  @doc "Returns the organization's current in-progress (draft) stock take at a site, or nil."
  def get_active_stock_take(organization_id, site_id) do
    Repo.get_by(StockTake, organization_id: organization_id, site_id: site_id, status: :draft)
  end

  @doc """
  Starts a new stock take at a site: creates the header and one entry per active batch
  currently at that site, snapshotting each batch's current `remaining_quantity` as the
  entry's `expected_quantity`. Fails with a changeset error (via the site's unique-draft
  index) if the site already has a stock take in progress.
  """
  def start_stock_take(organization_id, site_id, user_id, attrs \\ %{})
      when is_integer(organization_id) and is_integer(site_id) and is_integer(user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    changeset =
      %StockTake{}
      |> StockTake.changeset(attrs)
      |> Ecto.Changeset.put_change(:organization_id, organization_id)
      |> Ecto.Changeset.put_change(:site_id, site_id)
      |> Ecto.Changeset.put_change(:status, :draft)
      |> Ecto.Changeset.put_change(:started_at, now)
      |> Ecto.Changeset.put_change(:started_by_id, user_id)
      |> StockTake.finish_changeset()

    Repo.transaction(fn ->
      case Repo.insert(changeset) do
        {:ok, stock_take} ->
          organization_id
          |> Batches.list_active_batches_for_site(site_id)
          |> Enum.each(&insert_entry!(stock_take, &1))

          stock_take

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp insert_entry!(stock_take, batch) do
    %StockTakeEntry{}
    |> StockTakeEntry.changeset(%{
      stock_take_id: stock_take.id,
      batch_id: batch.id,
      expected_quantity: batch.remaining_quantity
    })
    |> Ecto.Changeset.put_change(:organization_id, stock_take.organization_id)
    |> Repo.insert!()
  end

  @doc """
  Records (or updates) the counted quantity for an entry. Returns `{:error, :not_draft}`
  without changing anything if the parent stock take has already been finalized.
  """
  def record_count(organization_id, entry_id, user_id, attrs) do
    entry = Repo.get_by!(StockTakeEntry, id: entry_id, organization_id: organization_id)
    stock_take = Repo.get!(StockTake, entry.stock_take_id)

    if stock_take.status == :draft do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      entry
      |> StockTakeEntry.count_changeset(attrs)
      |> Ecto.Changeset.put_change(:counted_by_id, user_id)
      |> Ecto.Changeset.put_change(:counted_at, now)
      |> StockTakeEntry.finish_count_changeset()
      |> Repo.update()
    else
      {:error, :not_draft}
    end
  end

  @doc """
  Finalizes a stock take: applies each counted entry whose batch hasn't drifted since
  counting began, and leaves any that have as an unapplied conflict for a follow-up recount.
  The stock take itself always moves to `:completed`, whether or not every entry applied.

  Returns `{:ok, stock_take, %{applied: [entry_ids], conflicted: [entry_ids]}}`, or
  `{:error, :not_draft}` if already finalized.
  """
  def finalize_stock_take(organization_id, id, user_id) do
    stock_take = get_stock_take!(organization_id, id)

    if stock_take.status == :draft do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, {completed, summary}} =
        Repo.transaction(fn ->
          results =
            stock_take.entries
            |> Enum.filter(&(&1.counted_quantity != nil))
            |> Enum.map(&apply_entry(organization_id, &1))

          {applied, conflicted} = Enum.split_with(results, &(&1.status == :applied))

          completed =
            stock_take
            |> Ecto.Changeset.change()
            |> Ecto.Changeset.put_change(:completed_by_id, user_id)
            |> Ecto.Changeset.put_change(:completed_at, now)
            |> StockTake.complete_changeset()
            |> Repo.update!()

          {completed,
           %{
             applied: Enum.map(applied, & &1.entry_id),
             conflicted: Enum.map(conflicted, & &1.entry_id)
           }}
        end)

      {:ok, completed, summary}
    else
      {:error, :not_draft}
    end
  end

  defp apply_entry(organization_id, entry) do
    batch = Batches.get_batch!(organization_id, entry.batch_id)

    if batch.remaining_quantity == entry.expected_quantity do
      {:ok, _batch} = Batches.set_remaining_quantity(batch, entry.counted_quantity)
      entry |> StockTakeEntry.apply_changeset() |> Repo.update!()
      %{entry_id: entry.id, status: :applied}
    else
      %{entry_id: entry.id, status: :conflicted}
    end
  end
end
