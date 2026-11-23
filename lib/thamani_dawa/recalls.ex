defmodule ThamaniDawa.Recalls do
  @moduledoc """
  Cross-organization batch tracing and recall lifecycle (§4.3.1).

  Deliberately breaks the organization-scoping convention every other
  context in this app follows — a recall has to see, and act on, every
  organization holding a batch, not just one. `trace/2`, `initiate_recall/6`,
  `list_recalls/1`, `get_recall!/1`, and `close/2` are reserved for
  `ThamaniDawa.Accounts.Scope.superadmin?/1`. `acknowledge_holder/2` is the
  one exception — any org admin may call it, but only for a holder that
  belongs to their own organization (checked inside the function, not just
  at the call site).

  A recall's per-holder state is kept minimal on purpose: whether a holder
  has been "reached and quarantined" is just whether its `RecallHolder` row
  exists and its batch is `:recalled` (already true the moment
  `initiate_recall/6` commits), and whether it's been "recovered" is read
  live off `batch.status` (`:destroyed`/`:returned`) rather than duplicated
  into a second field that could drift out of sync. The only state that
  doesn't exist anywhere else is acknowledgement, which is what
  `RecallHolder.acknowledged_at` is for.
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Accounts.UserNotifier
  alias ThamaniDawa.Batches
  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.Recalls.Recall
  alias ThamaniDawa.Recalls.RecallHolder
  alias ThamaniDawa.Repo

  @doc """
  Every batch matching `gtin` + `batch_no`, across every organization,
  each annotated with the outbound shipments drawn from it — the full
  network trail for one batch, used to preview who a recall would reach
  before one is issued. `batch.organization`, `batch.site`, and
  `batch.goods_receipt` are preloaded.
  """
  def trace(gtin, batch_no) when is_binary(gtin) and is_binary(batch_no) do
    Batch
    |> where([b], b.gtin == ^gtin and b.batch_no == ^batch_no)
    |> preload([:organization, :site, :goods_receipt])
    |> Repo.all()
    |> Enum.map(fn batch ->
      %{batch: batch, shipments: Batches.list_shipments_from_batch(batch)}
    end)
  end

  @doc """
  Issues a recall: inserts a `Recall`, snapshots a `RecallHolder` for every
  matching batch that still carries stock and isn't already `:recalled` or
  `:destroyed`, and cascades `Batches.mark_recalled/3` to each — all in one
  transaction. Emails every affected organization's admins afterwards.
  """
  def initiate_recall(gtin, batch_no, reference, classification, reason, user)
      when is_binary(gtin) and is_binary(batch_no) and is_binary(reference) and
             reference != "" and classification in [:class_i, :class_ii, :class_iii] do
    result =
      Repo.transaction(fn ->
        recall =
          %Recall{}
          |> Recall.create_changeset(%{
            gtin: gtin,
            batch_no: batch_no,
            reference: reference,
            classification: classification,
            reason: reason,
            initiated_by_id: user.id
          })
          |> Repo.insert!()

        updated =
          gtin
          |> trace(batch_no)
          |> Enum.map(& &1.batch)
          |> Enum.filter(
            &(&1.remaining_quantity > 0 and &1.status not in [:recalled, :destroyed])
          )
          |> Enum.map(&recall_batch(&1, recall, reference, user))

        {recall, updated}
      end)

    with {:ok, {recall, updated}} <- result do
      notify_holders(updated, gtin, batch_no, reference)
      {:ok, recall}
    end
  end

  defp recall_batch(batch, recall, reference, user) do
    %RecallHolder{}
    |> RecallHolder.create_changeset(%{
      recall_id: recall.id,
      organization_id: batch.organization_id,
      batch_id: batch.id,
      quantity_at_recall: batch.remaining_quantity
    })
    |> Repo.insert!()

    case Batches.mark_recalled(batch, reference, user) do
      {:ok, updated_batch} -> updated_batch
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp notify_holders(batches, gtin, batch_no, reference) do
    batches
    |> Enum.map(& &1.organization_id)
    |> Enum.uniq()
    |> Enum.each(fn organization_id ->
      organization_id
      |> Accounts.list_admins()
      |> Enum.each(&UserNotifier.deliver_recall_notice(&1, gtin, batch_no, reference))
    end)
  end

  @doc "Lists recalls newest first, optionally filtered to one status."
  def list_recalls(status \\ nil)

  def list_recalls(nil) do
    Repo.all(from r in Recall, order_by: [desc: r.inserted_at])
  end

  def list_recalls(status) when status in [:open, :closed] do
    Repo.all(from r in Recall, where: r.status == ^status, order_by: [desc: r.inserted_at])
  end

  @doc "Fetches a recall with its holders (and each holder's batch/organization/site) preloaded."
  def get_recall!(id) do
    Recall
    |> Repo.get!(id)
    |> Repo.preload(holders: [batch: [:organization, :site, :goods_receipt]])
  end

  @doc """
  The recall holder rows for one organization — every recalled batch it
  holds — newest recall first, with each holder's `recall` and `batch`
  preloaded. Pass `status` (`:open`/`:closed`) to filter by recall status.
  This is the organization's own view; it never exposes other holders.
  """
  def list_holders_for_organization(organization_id, status \\ nil) do
    query =
      from h in RecallHolder,
        join: r in assoc(h, :recall),
        where: h.organization_id == ^organization_id,
        order_by: [desc: r.inserted_at, asc: h.id],
        preload: [recall: r, batch: []]

    query =
      if status in [:open, :closed], do: where(query, [_h, r], r.status == ^status), else: query

    Repo.all(query)
  end

  @doc """
  Acknowledges a recall holder on behalf of its organization. Rejects the
  acknowledgement if `user` doesn't belong to the holder's organization —
  this is the one place a non-superadmin writes to a recall record.
  """
  def acknowledge_holder(holder_id, user) do
    holder = Repo.get!(RecallHolder, holder_id)

    if holder.organization_id == user.organization_id do
      holder
      |> RecallHolder.acknowledge_changeset(%{
        acknowledged_at: DateTime.truncate(DateTime.utc_now(), :second),
        acknowledged_by_id: user.id
      })
      |> Repo.update()
    else
      {:error, :not_authorized}
    end
  end

  @doc "Closes a recall. Does not require every holder to be acknowledged/recovered first — closing early is a superadmin's informed call, not a blocked one."
  def close(%Recall{} = recall, user) do
    recall
    |> Recall.close_changeset(%{
      closed_at: DateTime.truncate(DateTime.utc_now(), :second),
      closed_by_id: user.id
    })
    |> Repo.update()
  end

  @doc """
  Progress counters for a recall whose `holders` (and each holder's
  `batch`) are preloaded — `%{holders:, acknowledged:, units_total:,
  units_recovered:}`. "Recovered" is read live off each holder's batch
  status rather than stored, so it can't drift out of sync.
  """
  def progress(%Recall{holders: holders}) when is_list(holders) do
    %{
      holders: length(holders),
      acknowledged: Enum.count(holders, &(&1.acknowledged_at != nil)),
      units_total: Enum.sum(Enum.map(holders, & &1.quantity_at_recall)),
      units_recovered:
        holders
        |> Enum.filter(&(&1.batch.status in [:destroyed, :returned]))
        |> Enum.map(& &1.quantity_at_recall)
        |> Enum.sum()
    }
  end
end
