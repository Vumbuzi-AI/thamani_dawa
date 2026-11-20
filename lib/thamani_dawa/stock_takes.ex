defmodule ThamaniDawa.StockTakes do
  @moduledoc """
  Site- and stock-type-scoped stock take sessions. A session collects one
  auditable physical count per included batch, then is either applied
  directly by an admin or submitted by a requester for admin approval.

  Workflow: `draft` (counting) -> `pending` (submitted, awaiting review) ->
  `approved` (counted quantities applied) or `rejected` (no mutation). A
  pending session can be `reopened` back to draft by its requester. An
  admin may also go straight from `draft` to `approved`, skipping the
  request step, by opening the session with `admin_id` instead of
  `requested_by_id`.

  On approval, every counted item's batch has its `remaining_quantity` set
  directly to the counted value — physical count always wins, there is no
  separate write-off/disposal step. Uncounted items are left untouched.

  When a stock take is created, a count row is automatically materialised for
  every active (received and approved) batch at the site whose product
  matches the session's `inventory_type`, via `populate_items_for_site/3`.
  That function is idempotent — calling it again only adds rows for batches
  not yet represented, so it is safe to call on every page mount.
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.Repo
  alias ThamaniDawa.StockTakes.StockTake
  alias ThamaniDawa.StockTakes.StockTakeItem

  @tab_groups %{
    "draft" => [:draft],
    "pending" => [:pending],
    "approved" => [:approved],
    "rejected" => [:rejected]
  }

  @doc "The status tabs for a stock take queue, in display order."
  def tabs,
    do: [
      {"pending", "Pending"},
      {"draft", "Draft"},
      {"approved", "Approved"},
      {"rejected", "Rejected"}
    ]

  @doc "Counts `stock_takes` (already fetched/scoped) into each tab, for tab badges."
  def tab_counts(stock_takes) do
    Map.new(@tab_groups, fn {tab, statuses} ->
      {tab, Enum.count(stock_takes, &(&1.status in statuses))}
    end)
  end

  @doc "Filters an in-memory list of stock takes down to one status tab. `\"all\"` or an unknown tab returns every stock take."
  def filter_by_tab(stock_takes, tab) do
    case Map.get(@tab_groups, tab) do
      nil -> stock_takes
      statuses -> Enum.filter(stock_takes, &(&1.status in statuses))
    end
  end

  @doc "Lists all stock takes for an organization, newest first."
  def list_stock_takes(organization_id) do
    Repo.all(
      from st in StockTake,
        where: st.organization_id == ^organization_id,
        order_by: [desc: st.inserted_at],
        preload: [:site, :requested_by, :admin, :approved_by, :items]
    )
  end

  @doc "Lists stock takes for a specific site and stock type within an organization, newest first."
  def list_stock_takes_for_site(organization_id, site_id, inventory_type) do
    Repo.all(
      from st in StockTake,
        where: st.organization_id == ^organization_id,
        where: st.site_id == ^site_id,
        where: st.inventory_type == ^inventory_type,
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
    |> Repo.preload(
      items: {from(i in StockTakeItem, order_by: i.id), batch: batch_query},
      site: [],
      requested_by: [],
      admin: [],
      approved_by: []
    )
  end

  @doc "Returns a changeset for building or validating a stock take form."
  def change_stock_take(%StockTake{} = stock_take, attrs \\ %{}) do
    StockTake.create_changeset(stock_take, attrs)
  end

  @doc """
  Creates a new draft stock take for a site and stock type, and immediately
  populates a count row for every active batch of that type at that site.
  `attrs` must include `site_id` and `inventory_type`, and either
  `admin_id` or `requested_by_id`; `notes` is optional.
  """
  def create_stock_take(organization_id, attrs) when is_integer(organization_id) do
    Repo.transaction(fn ->
      with {:ok, stock_take} <-
             %StockTake{}
             |> StockTake.create_changeset(attrs)
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
  approved, with stock remaining) batch at `site_id` whose product matches
  the stock take's `inventory_type`. Batches that already have an item in
  this session are skipped. The snapshot `expected_quantity` is the batch's
  current `remaining_quantity` at the moment the row is inserted.

  Returns a list of `{:ok, item}` / `{:error, changeset}` tuples — one per
  batch that needed a new row.
  """
  def populate_items_for_site(%StockTake{} = stock_take, organization_id, site_id) do
    active_batches =
      Batches.list_active_batches_for_site_by_inventory_type(
        organization_id,
        site_id,
        stock_take.inventory_type
      )

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
  `{:error, :not_draft}` if the session is no longer a draft.
  """
  def add_item(%StockTake{status: :draft} = stock_take, %Batch{} = batch) do
    %StockTakeItem{}
    |> StockTakeItem.create_changeset(%{
      stock_take_id: stock_take.id,
      batch_id: batch.id,
      organization_id: stock_take.organization_id,
      expected_quantity: batch.remaining_quantity
    })
    |> Repo.audited_insert()
  end

  def add_item(%StockTake{}, _batch), do: {:error, :not_draft}

  @doc """
  Records the physical count for a stock take item, computing and storing the
  variance. Returns `{:error, :not_draft}` if the parent session is no
  longer a draft.
  """
  def record_count(%StockTakeItem{} = item, counted_quantity, user_id, attrs \\ %{}) do
    parent = Repo.get!(StockTake, item.stock_take_id)

    if parent.status != :draft do
      {:error, :not_draft}
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
  Submits a draft stock take for admin approval. Requires the caller to be
  the session's requester and at least one item to have been counted.
  Returns `{:error, :not_draft}`, `{:error, :not_requester}`, or
  `{:error, :no_counted_items}` on the relevant guard failures.
  """
  def submit_stock_take(organization_id, stock_take_id, requester_id) do
    Repo.transaction(fn ->
      with {:ok, locked} <- lock_stock_take(organization_id, stock_take_id),
           :ok <- ensure_status(locked, :draft),
           :ok <- ensure_requester(locked, requester_id),
           :ok <- ensure_any_counted(locked) do
        locked
        |> StockTake.submit_changeset()
        |> Repo.audited_update!()
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Approves a draft (admin self-serve) or pending (requester-submitted) stock
  take in a single transaction:

  1. Locks the stock take row `FOR UPDATE` to prevent concurrent approval.
  2. Verifies the session is `draft` or `pending`.
  3. For every item with a recorded count, locks its batch `FOR UPDATE` and
     sets `remaining_quantity` to the counted value (physical count wins).
     Uncounted items are left untouched.
  4. Marks the session `approved`, recording `approved_by_id`/`approved_at`.

  Returns `{:error, :not_approvable}` if the session isn't `draft`/`pending`.
  """
  def approve_stock_take(organization_id, stock_take_id, admin_id) do
    Repo.transaction(fn ->
      with {:ok, locked} <- lock_stock_take(organization_id, stock_take_id),
           :ok <- ensure_status(locked, [:draft, :pending]) do
        apply_counted_items(locked, organization_id)

        locked
        |> StockTake.approve_changeset(%{
          approved_by_id: admin_id,
          approved_at: DateTime.utc_now()
        })
        |> Repo.audited_update!()
      else
        {:error, _reason} -> Repo.rollback(:not_approvable)
      end
    end)
  end

  defp apply_counted_items(%StockTake{} = stock_take, organization_id) do
    items =
      Repo.all(
        from i in StockTakeItem,
          where: i.stock_take_id == ^stock_take.id,
          where: i.organization_id == ^organization_id,
          where: not is_nil(i.counted_quantity)
      )

    Enum.each(items, fn item ->
      Batch
      |> where([b], b.id == ^item.batch_id)
      |> lock("FOR UPDATE")
      |> Repo.one!()
      |> Batches.set_remaining_quantity(item.counted_quantity)
      |> case do
        {:ok, _batch} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Rejects a pending stock take with a required `rejection_reason`. No batch
  mutation occurs. Returns `{:error, :not_pending}` if the session isn't
  `:pending`.
  """
  def reject_stock_take(organization_id, stock_take_id, admin_id, rejection_reason) do
    Repo.transaction(fn ->
      with {:ok, locked} <- lock_stock_take(organization_id, stock_take_id),
           :ok <- ensure_status(locked, :pending) do
        apply_rejection(locked, admin_id, rejection_reason)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp apply_rejection(locked, admin_id, rejection_reason) do
    changeset =
      StockTake.reject_changeset(locked, %{
        approved_by_id: admin_id,
        approved_at: DateTime.utc_now(),
        rejection_reason: rejection_reason
      })

    case Repo.audited_update(changeset) do
      {:ok, rejected} -> rejected
      {:error, invalid_changeset} -> Repo.rollback(invalid_changeset)
    end
  end

  @doc """
  Reopens a pending stock take back to draft so its requester can keep
  counting. Requires the caller to be the session's requester. Returns
  `{:error, :not_pending}` or `{:error, :not_requester}`.
  """
  def reopen_stock_take(organization_id, stock_take_id, requester_id) do
    Repo.transaction(fn ->
      with {:ok, locked} <- lock_stock_take(organization_id, stock_take_id),
           :ok <- ensure_status(locked, :pending),
           :ok <- ensure_requester(locked, requester_id) do
        locked
        |> StockTake.reopen_changeset()
        |> Repo.audited_update!()
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp lock_stock_take(organization_id, stock_take_id) do
    case Repo.one(
           from st in StockTake,
             where: st.id == ^stock_take_id,
             where: st.organization_id == ^organization_id,
             lock: "FOR UPDATE"
         ) do
      nil -> {:error, :not_found}
      locked -> {:ok, locked}
    end
  end

  defp ensure_status(%StockTake{status: status}, expected) when is_list(expected) do
    if status in expected, do: :ok, else: {:error, :not_approvable}
  end

  defp ensure_status(%StockTake{status: status}, expected) do
    if status == expected, do: :ok, else: {:error, :"not_#{expected}"}
  end

  defp ensure_requester(%StockTake{requested_by_id: requested_by_id}, requester_id) do
    if requested_by_id == requester_id, do: :ok, else: {:error, :not_requester}
  end

  defp ensure_any_counted(%StockTake{id: stock_take_id}) do
    any_counted? =
      Repo.exists?(
        from i in StockTakeItem,
          where: i.stock_take_id == ^stock_take_id,
          where: not is_nil(i.counted_quantity)
      )

    if any_counted?, do: :ok, else: {:error, :no_counted_items}
  end
end
