defmodule ThamaniDawa.Batches do
  @moduledoc """
  The one unified batch table for both pharmacy and lab stock (§4.1) —
  `product_id` + `site_id` + GTIN/batch-lot/expiry, received either directly
  from a `supplier_id` or otherwise (§5).
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawa.Suppliers.Supplier

  @doc "Lists all batches for an organization."
  def list_batches(organization_id) do
    Repo.all(from b in Batch, where: b.organization_id == ^organization_id)
  end

  @doc """
  Lists all batches for an organization, one page at a time. When `site_ids`
  is given, restricts to batches at those sites — for staff assigned to a
  subset of the organization's sites; `nil` (the default) means org-wide.
  """
  def list_batches_paginated(organization_id, page \\ 1, site_ids \\ nil, opts \\ []) do
    query =
      from(b in Batch,
        join: p in ThamaniDawa.Products.Product,
        on: b.product_id == p.id,
        where: b.organization_id == ^organization_id,
        preload: [product: p]
      )

    query
    |> filter_by_site_ids(site_ids)
    |> filter_by_site_opt(Keyword.get(opts, :site))
    |> filter_by_status_opt(Keyword.get(opts, :status))
    |> filter_by_search_opt(Keyword.get(opts, :search))
    |> Repo.paginate(page: page)
  end

  defp filter_by_site_opt(query, site_id) when is_integer(site_id) do
    from([b, _p] in query, where: b.site_id == ^site_id)
  end

  defp filter_by_site_opt(query, site) when is_binary(site) and site != "" do
    case Integer.parse(site) do
      {site_id, ""} ->
        filter_by_site_opt(query, site_id)

      # A malformed filter value is dropped rather than raising. Safe because the
      # permitted-site scoping is a separate argument, applied independently.
      _ ->
        query
    end
  end

  defp filter_by_site_opt(query, _), do: query

  defp filter_by_status_opt(query, "active"),
    do: from([b, _p] in query, where: not is_nil(b.approver_id))

  defp filter_by_status_opt(query, "pending"),
    do: from([b, _p] in query, where: is_nil(b.approver_id))

  defp filter_by_status_opt(query, _), do: query

  defp filter_by_search_opt(query, search) when is_binary(search) and search != "" do
    pattern = "%#{String.trim(search)}%"

    from([b, p] in query,
      where:
        ilike(p.generic_name, ^pattern) or
          ilike(p.brand_name, ^pattern) or
          ilike(b.gtin, ^pattern) or
          ilike(b.batch_no, ^pattern)
    )
  end

  defp filter_by_search_opt(query, _), do: query

  @doc """
  Batch count and total remaining stock for each of the given product ids —
  the per-product roll-up shown when stock is browsed product-first rather
  than batch-first. When `site_ids` is given, restricts the roll-up to
  batches at those sites; `nil` (the default) means org-wide.
  """
  def stock_summary_by_product(organization_id, product_ids, site_ids \\ nil) do
    query =
      from(b in Batch,
        where: b.organization_id == ^organization_id,
        where: b.product_id in ^product_ids,
        group_by: b.product_id,
        select:
          {b.product_id,
           %{batch_count: count(b.id), total_remaining: coalesce(sum(b.remaining_quantity), 0)}}
      )

    query
    |> filter_by_site_ids(site_ids)
    |> Repo.all()
    |> Map.new()
  end

  defp filter_by_site_ids(query, nil), do: query
  defp filter_by_site_ids(query, site_ids), do: where(query, [b], b.site_id in ^site_ids)

  @doc "Lists batches dispatched to a site but not yet received by staff."
  def list_pending_batches(organization_id) do
    Repo.all(
      from b in Batch,
        where: b.organization_id == ^organization_id,
        where: is_nil(b.received_at)
    )
  end

  @doc "Lists batches dispatched to a specific site but not yet received by staff."
  def list_pending_batches_for_site(organization_id, site_id) do
    Repo.all(
      from b in Batch,
        where: b.organization_id == ^organization_id,
        where: b.site_id == ^site_id,
        where: is_nil(b.received_at)
    )
  end

  @doc "Lists active (received and approved) batches at a site."
  def list_active_batches_for_site(organization_id, site_id) do
    Repo.all(
      from b in Batch,
        where: b.organization_id == ^organization_id,
        where: b.site_id == ^site_id,
        where: not is_nil(b.received_at),
        where: not is_nil(b.approver_id),
        where: b.remaining_quantity > 0
    )
  end

  @doc """
  Finds approved batches by GTIN. 
  It filters by the provided `site_id`, but will also check if the GTIN is approved at 
  any *other* site within the organization to trigger the "Not at your site" transfer warning.
  """
  def find_approved_batches_by_gtin(organization_id, gtin, opts \\ [])
      when is_integer(organization_id) do
    query =
      from b in Batch,
        where: b.organization_id == ^organization_id,
        where: b.gtin == ^gtin,
        where: not is_nil(b.approver_id)

    site_id = Keyword.get(opts, :site_id)

    site_query =
      if site_id do
        from q in query, where: q.site_id == ^site_id
      else
        query
      end

    case Repo.all(site_query) do
      [] ->
        if site_id && Repo.exists?(query) do
          {:error, :not_at_site}
        else
          {:error, :not_found}
        end

      batches ->
        {:ok, batches}
    end
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

  @doc "Lists a product's batches, preloaded with `site`, `approver`, and `supplier` (all scoped to the organization)."
  def list_batches_for_product(organization_id, product_id, site_ids \\ nil) do
    site_query = from s in Site, where: s.organization_id == ^organization_id
    user_query = from u in User, where: u.organization_id == ^organization_id
    supplier_query = from s in Supplier, where: s.organization_id == ^organization_id

    query =
      from(b in Batch,
        where: b.organization_id == ^organization_id,
        where: b.product_id == ^product_id,
        order_by: [asc: b.expiry_date],
        preload: [site: ^site_query, approver: ^user_query, supplier: ^supplier_query]
      )

    query
    |> filter_by_site_ids(site_ids)
    |> Repo.all()
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

  @doc """
  Whether a site has ever had any batch record (any status, any stock
  level) for a product — i.e. whether this site's practice includes this
  product at all. Unlike `total_available_stock/3`, this is unaffected by
  a normal, temporary stock-out.
  """
  def any_batch_for_site?(organization_id, site_id, product_id) do
    Repo.exists?(
      from b in Batch,
        where: b.organization_id == ^organization_id,
        where: b.site_id == ^site_id,
        where: b.product_id == ^product_id
    )
  end

  @doc "Gets a single batch scoped to an organization. Raises if not found."
  def get_batch!(organization_id, id) do
    Repo.get_by!(Batch, id: id, organization_id: organization_id)
  end

  @doc """
  Gets a single batch scoped to an organization, preloaded with everything a
  traceability page needs — identity (`product`, `site`, `supplier`,
  `approver`) plus every event that has touched its stock (prescription
  dispenses, lab consumable usage, stock-take adjustments), each scoped to
  the same organization. Raises if not found.
  """
  def get_batch_with_details!(organization_id, id) do
    product_query = from p in Product, where: p.organization_id == ^organization_id
    site_query = from s in Site, where: s.organization_id == ^organization_id
    supplier_query = from s in Supplier, where: s.organization_id == ^organization_id
    user_query = from u in User, where: u.organization_id == ^organization_id

    Batch
    |> Repo.get_by!(id: id, organization_id: organization_id)
    |> Repo.preload(
      product: product_query,
      site: site_query,
      supplier: supplier_query,
      approver: user_query,
      prescription_batch_dispenses: [
        dispensed_by: user_query,
        prescription_item: [prescription: [patient_visit: :patient]]
      ],
      lab_consumable_usages: [used_by: user_query, lab_order: [patient_visit: :patient]],
      stock_take_items: [stock_take: [:finalized_by], counted_by: user_query]
    )
  end

  @doc """
  Dispatches a batch to a site. Sets product, site, quantity, and lot
  details. Approval fields (`received_at`, `approver_id`) are left unset —
  they are stamped on receipt via `receive_batch/2`.

  When `remaining_quantity` is omitted it defaults to `quantity`.
  """
  def create_batch(organization_id, attrs) when is_integer(organization_id) do
    %Batch{}
    |> Batch.changeset(default_remaining_quantity(attrs))
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> validate_belongs_to_org(:site_id, Site, organization_id)
    |> validate_belongs_to_org(:product_id, Product, organization_id)
    |> validate_belongs_to_org(:supplier_id, Supplier, organization_id)
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
  Returns all eligible batches for dispensing at `site_id` for `product_id`,
  ordered by soonest expiry (FEFO). Excludes pending or depleted batches.

  Locks rows `FOR UPDATE` to prevent concurrent oversubscription. Callers
  must execute within `Repo.transaction/1`.
  """
  def fefo_batches(organization_id, site_id, product_id) do
    if not Repo.in_transaction?() do
      raise "Batches.fefo_batches/3 must be called within a Repo.transaction/1 to safely lock stock"
    end

    query =
      from b in Batch,
        where: b.organization_id == ^organization_id,
        where: b.site_id == ^site_id,
        where: b.product_id == ^product_id,
        where: b.remaining_quantity > 0,
        where: not is_nil(b.approver_id),
        order_by: [asc: b.expiry_date, asc: b.id],
        lock: "FOR UPDATE"

    Repo.all(query)
  end

  @doc """
  Previews which batches `quantity` units would be drawn from, in FEFO
  order, without locking or mutating anything — for display purposes
  (e.g. showing a pharmacist which batch(es) dispensing will draw from).

  Unlike `fefo_batches/3`, this does not require a transaction and its
  result isn't authoritative: concurrent dispenses can change batch
  availability between this preview and the actual `dispense_item/4` call.

  Returns a list of `%{batch: batch, quantity: n}`, stopping once
  `quantity` is fully allocated. The last entry may take less than a
  batch's full `remaining_quantity` if that's all that's needed.
  """
  def preview_fefo_allocation(organization_id, site_id, product_id, quantity)
      when is_integer(quantity) and quantity > 0 do
    query =
      from b in Batch,
        where: b.organization_id == ^organization_id,
        where: b.site_id == ^site_id,
        where: b.product_id == ^product_id,
        where: b.remaining_quantity > 0,
        where: not is_nil(b.approver_id),
        order_by: [asc: b.expiry_date, asc: b.id]

    query
    |> Repo.all()
    |> allocate_preview(quantity)
  end

  defp allocate_preview([], _quantity_remaining), do: []
  defp allocate_preview(_batches, quantity_remaining) when quantity_remaining <= 0, do: []

  defp allocate_preview([batch | rest], quantity_remaining) do
    take = min(batch.remaining_quantity, quantity_remaining)
    [%{batch: batch, quantity: take} | allocate_preview(rest, quantity_remaining - take)]
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

  @doc """
  Sets `remaining_quantity` directly to `quantity` — a physical stock take correcting the
  recorded amount to match a fresh count, unlike `decrement_remaining_quantity/2`'s relative
  adjustment for a single dispense/consumption event.
  """
  def set_remaining_quantity(%Batch{} = batch, quantity) when is_integer(quantity) do
    batch
    |> Ecto.Changeset.change(remaining_quantity: quantity)
    |> Ecto.Changeset.validate_number(:remaining_quantity, greater_than_or_equal_to: 0)
    |> Repo.update()
  end
end
