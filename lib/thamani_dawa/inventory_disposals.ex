defmodule ThamaniDawa.InventoryDisposals do
  @moduledoc """
  Site- and stock-type-scoped inventory disposal requests, for removing
  stock from the system via expiry write-off or supplier return.

  Workflow: `draft` (requester picks batches and quantities) -> `pending`
  (submitted, awaiting review) -> `approved` (quantities applied) or
  `rejected` (no mutation). A pending disposal can be `reopened` back to
  draft by its requester. An admin may also go straight from `draft` to
  `approved`, skipping the request step, by opening the disposal with
  `admin_id` instead of `requested_by_id`.

  Unlike `ThamaniDawa.StockTakes`, a disposal starts empty — the requester
  deliberately picks which batches to dispose rather than every batch at
  the site being auto-populated, since this removes stock rather than
  counting it.

  On approval, each item's batch has `remaining_quantity` decremented by
  the requested `quantity`. If that decrement fully empties a batch that
  was still `:active`, the batch's `status` is also transitioned —
  `:expired` for an expiry disposal, `:returned` for a supplier return.
  Partial disposals, or disposals of a batch that wasn't `:active` to
  begin with (e.g. `:quarantined`), only decrement the quantity and leave
  `status` untouched.
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.Epcis
  alias ThamaniDawa.InventoryDisposals.InventoryDisposal
  alias ThamaniDawa.InventoryDisposals.InventoryDisposalItem
  alias ThamaniDawa.Repo

  @tab_groups %{
    "draft" => [:draft],
    "pending" => [:pending],
    "approved" => [:approved],
    "rejected" => [:rejected]
  }

  @doc "The status tabs for a disposal queue, in display order."
  def tabs,
    do: [
      {"pending", "Pending"},
      {"draft", "Draft"},
      {"approved", "Approved"},
      {"rejected", "Rejected"}
    ]

  @doc "Counts `disposals` (already fetched/scoped) into each tab, for tab badges."
  def tab_counts(disposals) do
    Map.new(@tab_groups, fn {tab, statuses} ->
      {tab, Enum.count(disposals, &(&1.status in statuses))}
    end)
  end

  @doc "Filters an in-memory list of disposals down to one status tab. `\"all\"` or an unknown tab returns every disposal."
  def filter_by_tab(disposals, tab) do
    case Map.get(@tab_groups, tab) do
      nil -> disposals
      statuses -> Enum.filter(disposals, &(&1.status in statuses))
    end
  end

  @doc "Lists all disposals for an organization, newest first."
  def list_disposals(organization_id) do
    Repo.all(
      from d in InventoryDisposal,
        where: d.organization_id == ^organization_id,
        order_by: [desc: d.inserted_at],
        preload: [:site, :requested_by, :admin, :approved_by, :items]
    )
  end

  @doc "Lists disposals for a specific site, kind, and stock type within an organization, newest first."
  def list_disposals_for_site(organization_id, site_id, kind, inventory_type) do
    Repo.all(
      from d in InventoryDisposal,
        where: d.organization_id == ^organization_id,
        where: d.site_id == ^site_id,
        where: d.kind == ^kind,
        where: d.inventory_type == ^inventory_type,
        order_by: [desc: d.inserted_at]
    )
  end

  @doc """
  Gets a single disposal scoped to an organization, preloaded with items,
  each item's batch (and its supplier), and the parties involved. Raises
  if not found.
  """
  def get_disposal!(organization_id, id) do
    batch_query =
      from b in Batch, where: b.organization_id == ^organization_id, preload: [:supplier]

    InventoryDisposal
    |> Repo.get_by!(id: id, organization_id: organization_id)
    |> Repo.preload(
      items: {from(i in InventoryDisposalItem, order_by: i.id), batch: batch_query},
      site: [],
      requested_by: [],
      admin: [],
      approved_by: []
    )
  end

  @doc "Returns a changeset for building or validating a disposal form."
  def change_disposal(%InventoryDisposal{} = disposal, attrs \\ %{}) do
    InventoryDisposal.create_changeset(disposal, attrs)
  end

  @doc """
  Creates a new draft disposal for a site. `attrs` must include `site_id`,
  `kind`, and `inventory_type`, and either `admin_id` or `requested_by_id`;
  `reason`/`notes` are optional. Starts with no items — the requester adds
  batches explicitly via `add_item/3`.
  """
  def create_disposal(organization_id, attrs) when is_integer(organization_id) do
    %InventoryDisposal{}
    |> InventoryDisposal.create_changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.audited_insert()
  end

  @doc """
  Adds a batch to a draft disposal, requesting `quantity` units be
  disposed. Snapshots the batch's current `remaining_quantity` as
  `available_quantity`.

  An `:expiry` write-off only accepts a lot past its date, and the quantity
  must be the whole remaining amount — a partial write-off would leave the
  rest saleable. A `:returned` disposal requires a recorded supplier, and
  may return part of the lot. Returns `{:error, :not_draft}` if the disposal
  is no longer a draft, `{:error, :not_expired}` or `{:error, :partial_expiry}`
  for an expiry write-off, or `{:error, :no_supplier}` for a supplier-less
  batch on a `:returned` disposal.
  """
  def add_item(%InventoryDisposal{status: :draft} = disposal, %Batch{} = batch, quantity) do
    cond do
      disposal.kind == :returned and is_nil(batch.supplier_id) ->
        {:error, :no_supplier}

      disposal.kind == :expiry and not expired_batch?(batch) ->
        {:error, :not_expired}

      disposal.kind == :expiry and quantity != batch.remaining_quantity ->
        {:error, :partial_expiry}

      true ->
        %InventoryDisposalItem{}
        |> InventoryDisposalItem.create_changeset(%{
          inventory_disposal_id: disposal.id,
          batch_id: batch.id,
          organization_id: disposal.organization_id,
          available_quantity: batch.remaining_quantity,
          quantity: quantity
        })
        |> Repo.audited_insert()
    end
  end

  def add_item(%InventoryDisposal{}, _batch, _quantity), do: {:error, :not_draft}

  defp expired_batch?(%Batch{expiry_date: %Date{} = expiry_date}) do
    Date.compare(expiry_date, Date.utc_today()) == :lt
  end

  defp expired_batch?(_batch), do: false

  @doc """
  Removes an item from a draft disposal. Returns `{:error, :not_draft}` if
  the parent disposal is no longer a draft.
  """
  def remove_item(%InventoryDisposalItem{} = item) do
    parent = Repo.get!(InventoryDisposal, item.inventory_disposal_id)

    if parent.status != :draft do
      {:error, :not_draft}
    else
      Repo.audited_delete(item)
    end
  end

  @doc """
  Submits a draft disposal for admin approval. Requires the caller to be
  the disposal's requester, at least one item, and that every item's
  requested `quantity` is still available on its batch (stock may have
  moved since the item was added). Returns `{:error, :not_draft}`,
  `{:error, :not_requester}`, `{:error, :no_items}`, or
  `{:error, {:stock_changed, item_id}}` on the relevant guard failures.
  """
  def submit_disposal(organization_id, disposal_id, requester_id) do
    Repo.transaction(fn ->
      with {:ok, locked} <- lock_disposal(organization_id, disposal_id),
           :ok <- ensure_status(locked, :draft),
           :ok <- ensure_requester(locked, requester_id),
           :ok <- ensure_any_items(locked),
           :ok <- revalidate_items_against_current_stock(locked) do
        locked
        |> InventoryDisposal.submit_changeset()
        |> Repo.audited_update!()
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp revalidate_items_against_current_stock(%InventoryDisposal{id: disposal_id}) do
    items =
      Repo.all(from i in InventoryDisposalItem, where: i.inventory_disposal_id == ^disposal_id)

    Enum.reduce_while(items, :ok, fn item, :ok ->
      case Repo.get(Batch, item.batch_id) do
        %Batch{remaining_quantity: remaining} when item.quantity > remaining ->
          {:halt, {:error, {:stock_changed, item.id}}}

        _ ->
          {:cont, :ok}
      end
    end)
  end

  @doc """
  Approves a draft (admin self-serve) or pending (requester-submitted)
  disposal in a single transaction:

  1. Locks the disposal row `FOR UPDATE`.
  2. Verifies the disposal is `draft` or `pending`.
  3. For every item, locks its batch `FOR UPDATE` and decrements
     `remaining_quantity` by the requested `quantity`. If that empties a
     batch that was still `:active`, also transitions the batch's status
     (`:expired` or `:returned`, per the disposal's `kind`).
  4. Marks the disposal `approved`, recording `approved_by_id`/`approved_at`.

  Returns `{:error, :not_approvable}` if the disposal isn't `draft`/`pending`.
  """
  def approve_disposal(organization_id, disposal_id, admin_id) do
    Repo.transaction(fn ->
      with {:ok, locked} <- lock_disposal(organization_id, disposal_id),
           :ok <- ensure_status(locked, [:draft, :pending]) do
        apply_disposal_items(locked, organization_id, admin_id)

        locked
        |> InventoryDisposal.approve_changeset(%{
          approved_by_id: admin_id,
          approved_at: DateTime.utc_now()
        })
        |> Repo.audited_update!()
      else
        {:error, _reason} -> Repo.rollback(:not_approvable)
      end
    end)
  end

  defp apply_disposal_items(%InventoryDisposal{} = disposal, organization_id, admin_id) do
    items =
      Repo.all(
        from i in InventoryDisposalItem,
          where: i.inventory_disposal_id == ^disposal.id,
          where: i.organization_id == ^organization_id
      )

    Enum.each(items, &apply_disposal_item(&1, disposal, admin_id))
  end

  defp apply_disposal_item(item, %InventoryDisposal{} = disposal, admin_id) do
    batch =
      Batch
      |> where([b], b.id == ^item.batch_id)
      |> lock("FOR UPDATE")
      |> Repo.one!()

    case Batches.decrement_remaining_quantity(batch, item.quantity) do
      {:ok, %Batch{remaining_quantity: 0, status: :active} = decremented} ->
        maybe_transition_status(decremented, disposal, admin_id)

      {:ok, decremented} ->
        record_disposal_status(decremented, disposal)

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp record_disposal_status(batch, disposal) do
    case disposal.kind do
      :expiry ->
        Epcis.record_batch_status(batch, "expired", "inspecting", "expired", nil, nil)

      :returned ->
        Epcis.record_batch_status(
          batch,
          "returned",
          "returning",
          "returned",
          "DISPOSAL-#{disposal.id}",
          "return"
        )
    end
  end

  defp maybe_transition_status(
         %Batch{remaining_quantity: 0, status: :active} = batch,
         disposal,
         admin_id
       ) do
    result =
      case disposal.kind do
        :expiry -> Batches.mark_expired(batch, admin_id)
        :returned -> Batches.mark_returned(batch, "DISPOSAL-#{disposal.id}", admin_id)
      end

    case result do
      {:ok, _batch} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp maybe_transition_status(_batch, _disposal, _admin_id), do: :ok

  @doc """
  Rejects a pending disposal with a required `rejection_reason`. No batch
  mutation occurs. Returns `{:error, :not_pending}` if the disposal isn't
  `:pending`.
  """
  def reject_disposal(organization_id, disposal_id, admin_id, rejection_reason) do
    Repo.transaction(fn ->
      with {:ok, locked} <- lock_disposal(organization_id, disposal_id),
           :ok <- ensure_status(locked, :pending) do
        apply_rejection(locked, admin_id, rejection_reason)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp apply_rejection(locked, admin_id, rejection_reason) do
    changeset =
      InventoryDisposal.reject_changeset(locked, %{
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
  Reopens a pending disposal back to draft so its requester can keep
  editing. Requires the caller to be the disposal's requester. Returns
  `{:error, :not_pending}` or `{:error, :not_requester}`.
  """
  def reopen_disposal(organization_id, disposal_id, requester_id) do
    Repo.transaction(fn ->
      with {:ok, locked} <- lock_disposal(organization_id, disposal_id),
           :ok <- ensure_status(locked, :pending),
           :ok <- ensure_requester(locked, requester_id) do
        locked
        |> InventoryDisposal.reopen_changeset()
        |> Repo.audited_update!()
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp lock_disposal(organization_id, disposal_id) do
    case Repo.one(
           from d in InventoryDisposal,
             where: d.id == ^disposal_id,
             where: d.organization_id == ^organization_id,
             lock: "FOR UPDATE"
         ) do
      nil -> {:error, :not_found}
      locked -> {:ok, locked}
    end
  end

  defp ensure_status(%InventoryDisposal{status: status}, expected) when is_list(expected) do
    if status in expected, do: :ok, else: {:error, :not_approvable}
  end

  defp ensure_status(%InventoryDisposal{status: status}, expected) do
    if status == expected, do: :ok, else: {:error, :"not_#{expected}"}
  end

  defp ensure_requester(%InventoryDisposal{requested_by_id: requested_by_id}, requester_id) do
    if requested_by_id == requester_id, do: :ok, else: {:error, :not_requester}
  end

  defp ensure_any_items(%InventoryDisposal{id: disposal_id}) do
    any_items? =
      Repo.exists?(
        from i in InventoryDisposalItem, where: i.inventory_disposal_id == ^disposal_id
      )

    if any_items?, do: :ok, else: {:error, :no_items}
  end
end
