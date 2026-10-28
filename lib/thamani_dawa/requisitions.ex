defmodule ThamaniDawa.Requisitions do
  @moduledoc """
  Site-to-organization stock requests. A site raises a requisition for a
  product and quantity; an org admin approves or rejects it, then fulfills
  an approved requisition by dispatching organization stock against it (see
  `fulfill_requisition/4`). Fulfillment status is always computed from the
  batches actually dispatched against a requisition, never hand-set.
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Requisitions.Requisition
  alias ThamaniDawa.Sites.Site

  @doc "Lists all requisitions for an organization, newest first."
  def list_requisitions(organization_id) do
    Repo.all(
      from r in Requisition,
        where: r.organization_id == ^organization_id,
        order_by: [desc: r.inserted_at]
    )
  end

  @doc "Counts requisitions still awaiting review (status `:pending`) for an organization."
  def count_pending(organization_id) do
    Repo.aggregate(
      from(r in Requisition,
        where: r.organization_id == ^organization_id and r.status == :pending
      ),
      :count
    )
  end

  @doc "Lists requisitions raised by a specific site, newest first."
  def list_requisitions_for_site(organization_id, site_id) do
    Repo.all(
      from r in Requisition,
        where: r.organization_id == ^organization_id,
        where: r.site_id == ^site_id,
        order_by: [desc: r.inserted_at]
    )
  end

  @doc """
  Gets a single requisition scoped to an organization, preloaded with
  `product`, `site`, `requested_by`, and `reviewed_by`. Raises if not found.
  """
  def get_requisition!(organization_id, id) do
    Requisition
    |> Repo.get_by!(id: id, organization_id: organization_id)
    |> Repo.preload([:product, :site, :requested_by, :reviewed_by])
  end

  @doc "Returns a changeset for building or validating a requisition form."
  def change_requisition(%Requisition{} = requisition, attrs \\ %{}) do
    Requisition.create_changeset(requisition, attrs)
  end

  @doc """
  Creates a requisition for a site. `attrs` must include `site_id`,
  `product_id`, and `quantity`; `urgency`/`notes` are optional.
  `organization_id`/`requested_by_id` come from the caller's scope, not attrs.
  """
  def create_requisition(organization_id, requested_by_id, attrs)
      when is_integer(organization_id) and is_integer(requested_by_id) do
    %Requisition{}
    |> Requisition.create_changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Ecto.Changeset.put_change(:requested_by_id, requested_by_id)
    |> validate_belongs_to_org(:site_id, Site, organization_id)
    |> validate_belongs_to_org(:product_id, Product, organization_id)
    |> validate_belongs_to_org(:requested_by_id, User, organization_id)
    |> Repo.audited_insert()
  end

  @doc """
  Approves a pending requisition. Locks the row `FOR UPDATE` to prevent a
  concurrent approve/reject, then computes and persists `needs_reorder` by
  comparing organization-level available stock against the requested
  quantity. Returns `{:error, :not_pending}` if the requisition isn't
  `:pending`.
  """
  def approve_requisition(organization_id, requisition_id, reviewer_id) do
    with :ok <- validate_user_organization(organization_id, reviewer_id) do
      Repo.transaction(fn -> approve_locked(organization_id, requisition_id, reviewer_id) end)
    end
  end

  defp approve_locked(organization_id, requisition_id, reviewer_id) do
    case lock_pending(organization_id, requisition_id) do
      {:ok, locked} -> approve_locked_requisition(locked, organization_id, reviewer_id)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp approve_locked_requisition(locked, organization_id, reviewer_id) do
    locked
    |> Requisition.review_changeset(%{
      status: :approved,
      reviewed_by_id: reviewer_id,
      reviewed_at: DateTime.utc_now(),
      needs_reorder: needs_reorder?(organization_id, locked.product_id, locked.quantity)
    })
    |> update_or_rollback()
  end

  @doc """
  Rejects a pending requisition with a required `rejection_reason`. Same
  locking as `approve_requisition/3`.
  """
  def reject_requisition(organization_id, requisition_id, reviewer_id, rejection_reason) do
    with :ok <- validate_user_organization(organization_id, reviewer_id) do
      Repo.transaction(fn ->
        reject_locked(organization_id, requisition_id, reviewer_id, rejection_reason)
      end)
    end
  end

  defp reject_locked(organization_id, requisition_id, reviewer_id, rejection_reason) do
    case lock_pending(organization_id, requisition_id) do
      {:ok, locked} -> reject_locked_requisition(locked, reviewer_id, rejection_reason)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp reject_locked_requisition(locked, reviewer_id, rejection_reason) do
    locked
    |> Requisition.review_changeset(%{
      status: :rejected,
      reviewed_by_id: reviewer_id,
      reviewed_at: DateTime.utc_now(),
      rejection_reason: rejection_reason
    })
    |> update_or_rollback()
  end

  defp update_or_rollback(changeset) do
    case Repo.audited_update(changeset) do
      {:ok, record} -> record
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_pending(organization_id, requisition_id) do
    locked =
      Repo.one(
        from r in Requisition,
          where: r.id == ^requisition_id and r.organization_id == ^organization_id,
          lock: "FOR UPDATE"
      )

    cond do
      is_nil(locked) -> {:error, :not_found}
      locked.status != :pending -> {:error, :not_pending}
      true -> {:ok, locked}
    end
  end

  @doc """
  Whether organization-level available stock for `product_id` is less than
  `quantity` — the signal surfaced to admins that fulfilling this
  requisition (now or later) will require ordering more stock.
  """
  def needs_reorder?(organization_id, product_id, quantity) do
    available =
      organization_id
      |> ThamaniDawa.Batches.undispatched_summary_by_product([product_id])
      |> Map.get(product_id, 0)

    available < quantity
  end

  @doc """
  Sum of `quantity` across every batch dispatched against this requisition
  — i.e. total units actually moved, regardless of how much of that stock
  has since been dispensed. `quantity` is immutable at dispatch time, so
  this is stable even as `remaining_quantity` drifts down.
  """
  def fulfilled_quantity(requisition_id) do
    Repo.one(
      from b in Batch,
        where: b.requisition_id == ^requisition_id,
        select: coalesce(sum(b.quantity), 0)
    )
  end

  @doc """
  Fulfills part or all of an approved requisition by dispatching `quantity`
  units from `org_batch` to the requisition's site (reusing
  `Batches.dispatch_to_site/3`), tagging the resulting site batch with the
  requisition's id, and recomputing the requisition's status from the total
  fulfilled so far. All in one transaction.

  Returns `{:error, :not_approved}` if the requisition isn't `:approved` or
  already fully `:fulfilled`, or propagates whatever error
  `Batches.dispatch_to_site/3` returns (e.g. `:insufficient_quantity`).
  """
  def fulfill_requisition(organization_id, requisition_id, %Batch{} = org_batch, quantity) do
    Repo.transaction(fn ->
      fulfill_locked(organization_id, requisition_id, org_batch.id, quantity)
    end)
  end

  defp fulfill_locked(organization_id, requisition_id, batch_id, quantity) do
    with {:ok, locked} <- lock_fulfillable(organization_id, requisition_id),
         {:ok, current_batch} <- get_organization_batch(organization_id, batch_id),
         :ok <- validate_fulfillment(locked, current_batch, quantity) do
      dispatch_and_recompute(locked, current_batch, quantity)
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp get_organization_batch(organization_id, batch_id) do
    case Repo.get_by(Batch, id: batch_id, organization_id: organization_id) do
      nil -> {:error, :batch_not_found}
      batch -> {:ok, batch}
    end
  end

  defp validate_fulfillment(requisition, batch, quantity) do
    remaining_requested = requisition.quantity - fulfilled_quantity(requisition.id)

    cond do
      batch.product_id != requisition.product_id -> {:error, :product_mismatch}
      not is_integer(quantity) or quantity <= 0 -> {:error, :invalid_dispatch_quantity}
      quantity > remaining_requested -> {:error, :exceeds_requested_quantity}
      true -> :ok
    end
  end

  defp lock_fulfillable(organization_id, requisition_id) do
    locked =
      Repo.one(
        from r in Requisition,
          where: r.id == ^requisition_id and r.organization_id == ^organization_id,
          lock: "FOR UPDATE"
      )

    cond do
      is_nil(locked) -> {:error, :not_found}
      locked.status not in [:approved, :partially_fulfilled] -> {:error, :not_approved}
      true -> {:ok, locked}
    end
  end

  defp dispatch_and_recompute(%Requisition{} = requisition, org_batch, quantity) do
    with {:ok, dispatched} <-
           ThamaniDawa.Batches.dispatch_to_site(org_batch, requisition.site_id, quantity),
         {:ok, _tagged} <- tag_requisition(dispatched, requisition.id) do
      recompute_status(requisition)
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp tag_requisition(batch, requisition_id) do
    batch |> Ecto.Changeset.change(requisition_id: requisition_id) |> Repo.audited_update()
  end

  defp recompute_status(%Requisition{} = requisition) do
    fulfilled = fulfilled_quantity(requisition.id)

    status =
      cond do
        fulfilled >= requisition.quantity -> :fulfilled
        fulfilled > 0 -> :partially_fulfilled
        true -> requisition.status
      end

    requisition
    |> Ecto.Changeset.change(status: status)
    |> Repo.audited_update!()
  end

  defp validate_belongs_to_org(changeset, field, schema, organization_id) do
    case Ecto.Changeset.get_field(changeset, field) do
      nil ->
        changeset

      id ->
        if Repo.exists?(
             from record in schema,
               where: record.id == ^id and record.organization_id == ^organization_id
           ) do
          changeset
        else
          Ecto.Changeset.add_error(changeset, field, "does not belong to this organization")
        end
    end
  end

  defp validate_user_organization(organization_id, user_id) do
    if Repo.exists?(
         from u in User,
           where: u.id == ^user_id and u.organization_id == ^organization_id
       ) do
      :ok
    else
      {:error, :invalid_reviewer}
    end
  end
end
