defmodule ThamaniDawa.Batches do
  @moduledoc """
  The one unified batch table for both pharmacy and lab stock (§4.1) —
  `product_id` + `site_id` + GTIN/batch-lot/expiry, received either directly
  from a `supplier_id` or otherwise (§5).
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites.Site

  @doc "Lists all batches for an organization."
  def list_batches(organization_id) do
    Repo.all(from b in Batch, where: b.organization_id == ^organization_id)
  end

  @doc "Lists batches dispatched to a site but not yet received by staff."
  def list_pending_batches(organization_id) do
    Repo.all(
      from b in Batch,
        where: b.organization_id == ^organization_id,
        where: is_nil(b.received_at)
    )
  end

  @doc "Lists pending (not yet received) batches dispatched to a specific site."
  def list_pending_batches_for_site(organization_id, site_id) do
    Repo.all(
      from b in Batch,
        where: b.organization_id == ^organization_id,
        where: b.site_id == ^site_id,
        where: is_nil(b.received_at),
        order_by: [asc: b.expiry_date]
    )
  end

  @doc "Lists active (received, stock remaining) batches at a specific site."
  def list_active_batches_for_site(organization_id, site_id) do
    Repo.all(
      from b in Batch,
        where: b.organization_id == ^organization_id,
        where: b.site_id == ^site_id,
        where: not is_nil(b.approver_id),
        where: b.remaining_quantity > 0,
        order_by: [asc: b.expiry_date]
    )
  end

  @doc """
  Finds the pending (not yet received) batch matching a scanned GTIN and
  batch/lot number, for resolving a GS1 scan to the dispatch it's confirming
  receipt of. Pass `site_id:` to narrow the search to one site.
  """
  def find_pending_batch(organization_id, gtin, batch_no, opts \\ []) do
    query =
      from b in Batch,
        where: b.organization_id == ^organization_id,
        where: b.gtin == ^gtin,
        where: b.batch_no == ^batch_no,
        where: is_nil(b.received_at)

    query =
      if site_id = Keyword.get(opts, :site_id) do
        from q in query, where: q.site_id == ^site_id
      else
        query
      end

    case Repo.one(query) do
      nil -> {:error, :not_found}
      batch -> {:ok, batch}
    end
  end

  def list_batches_for_product(organization_id, product_id) do
    Repo.all(
      from b in Batch,
        where: b.organization_id == ^organization_id,
        where: b.product_id == ^product_id,
        order_by: [asc: b.expiry_date]
    )
  end

  @doc "Gets the total sum of remaining quantity of approved stock for a product at a given site."
  def total_available_stock(organization_id, site_id, product_id) do
    case Repo.one(
           from b in Batch,
             where: b.organization_id == ^organization_id,
             where: b.site_id == ^site_id,
             where: b.product_id == ^product_id,
             where: b.remaining_quantity > 0,
             where: not is_nil(b.approver_id),
             select: sum(b.remaining_quantity)
         ) do
      nil -> 0
      %Decimal{} = d -> Decimal.to_integer(d)
      n when is_integer(n) -> n
    end
  end

  @doc "Gets a single batch scoped to an organization. Raises if not found."
  def get_batch!(organization_id, id) do
    Repo.get_by!(Batch, id: id, organization_id: organization_id)
  end

  @doc """
  Dispatches a batch to a site. Sets product, site, quantity, and lot
  details. Approval fields (`received_by_id`, `received_at`, `approver_id`,
  `is_approved`) are left unset — they are stamped on receipt via
  `receive_batch/2`.

  When `remaining_quantity` is omitted it defaults to `quantity`.
  """
  def create_batch(organization_id, attrs) when is_integer(organization_id) do
    %Batch{}
    |> Batch.changeset(default_remaining_quantity(attrs))
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> validate_belongs_to_org(:site_id, Site, organization_id)
    |> validate_belongs_to_org(:product_id, Product, organization_id)
    |> Repo.insert()
  end

  @doc """
  Marks a batch as received by `user_id`, stamping `approver_id`/`received_at`
  and making it active for dispensing or lab consumption. Pass a `"quantity"`
  in `attrs` when the amount actually received differs from what was
  dispatched — `remaining_quantity` is reset to match, since a pending batch
  can't yet have anything dispensed from it.
  """
  def receive_batch(%Batch{} = batch, user_id, attrs \\ %{}) do
    attrs =
      Map.merge(attrs, %{
        "received_by_id" => user_id,
        "received_at" => DateTime.utc_now(),
        "approver_id" => user_id
      })

    batch
    |> Batch.receive_changeset(attrs)
    |> Repo.update()
  end

  defp validate_belongs_to_org(changeset, field, schema, organization_id) do
    Ecto.Changeset.validate_change(changeset, field, fn _field, id ->
      case Repo.get_by(schema, id: id, organization_id: organization_id) do
        nil -> [{field, "does not belong to this organization"}]
        _record -> []
      end
    end)
  end

  defp default_remaining_quantity(attrs) do
    has_remaining? =
      Map.has_key?(attrs, :remaining_quantity) or Map.has_key?(attrs, "remaining_quantity")

    {quantity, string_keys?} =
      cond do
        Map.has_key?(attrs, "quantity") -> {Map.get(attrs, "quantity"), true}
        Map.has_key?(attrs, :quantity) -> {Map.get(attrs, :quantity), false}
        true -> {nil, false}
      end

    if has_remaining? or is_nil(quantity) do
      attrs
    else
      key = if string_keys?, do: "remaining_quantity", else: :remaining_quantity
      Map.put(attrs, key, quantity)
    end
  end

  @doc """
  Picks the batch to dispense/consume from at `site_id` for `product_id`,
  per FEFO (first-expired-first-out, §9): the active, approved batch with
  stock remaining, soonest expiry first. Pending (not yet received) batches
  are excluded. This query is what enforces §4.3's "batch must be at the
  prescription's own site_id" for pharmacy dispensing — a batch at any other
  site is never a candidate.

  Locks the returned row `FOR UPDATE`, so callers must run this inside
  `Repo.transaction/1` and decrement the batch before the transaction ends,
  to prevent two concurrent dispenses from oversubscribing the same stock.
  Returns `{:error, :out_of_stock}` when no eligible batch exists.
  """
  def fefo_batch(organization_id, site_id, product_id) do
    query =
      from b in Batch,
        where: b.organization_id == ^organization_id,
        where: b.site_id == ^site_id,
        where: b.product_id == ^product_id,
        where: b.remaining_quantity > 0,
        where: not is_nil(b.approver_id),
        order_by: [asc: b.expiry_date],
        limit: 1,
        lock: "FOR UPDATE"

    case Repo.one(query) do
      nil -> {:error, :out_of_stock}
      batch -> {:ok, batch}
    end
  end

  @doc """
  Decrements `remaining_quantity` by `quantity` — stock leaving a batch via
  dispensing or lab consumption. Returns `{:error, changeset}` if that
  would take it below zero.
  """
  def decrement_remaining_quantity(%Batch{} = batch, quantity)
      when is_integer(quantity) and quantity > 0 do
    batch
    |> Ecto.Changeset.change(remaining_quantity: batch.remaining_quantity - quantity)
    |> Ecto.Changeset.validate_number(:remaining_quantity, greater_than_or_equal_to: 0)
    |> Repo.update()
  end
end
