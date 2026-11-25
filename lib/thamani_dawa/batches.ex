defmodule ThamaniDawa.Batches do
  @moduledoc """
  The one unified batch table for both pharmacy and lab stock (§4.1) —
  `product_id` + `site_id` + GTIN/batch-lot/expiry, received either directly
  from a `supplier_id` or otherwise (§5).
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.Batches.LogisticUnit
  alias ThamaniDawa.Distributor.Shipment
  alias ThamaniDawa.Distributor.ShipmentItem
  alias ThamaniDawa.Epcis
  alias ThamaniDawa.GS1.MemberApi
  alias ThamaniDawa.GoodsReceipts.GoodsReceipt
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawa.Suppliers.Supplier

  @doc "Lists all batches for an organization."
  def list_batches(organization_id) do
    Repo.all(from b in Batch, where: b.organization_id == ^organization_id)
  end

  @doc "Fetches a logistic unit (case/SSCC) scoped to an organization, with its site preloaded."
  def get_logistic_unit!(organization_id, id) do
    LogisticUnit
    |> Repo.get_by!(id: id, organization_id: organization_id)
    |> Repo.preload(:site)
  end

  @doc "Active, in-stock batch lines belonging to a logistic unit (a case's contents)."
  def list_case_lines(organization_id, logistic_unit_id) do
    Repo.all(
      from b in Batch,
        where:
          b.organization_id == ^organization_id and b.logistic_unit_id == ^logistic_unit_id and
            b.status == :active and b.remaining_quantity > 0,
        order_by: [asc: b.batch_no],
        preload: [:product]
    )
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
  than batch-first. Restricted to batches actually dispatched to a site
  (org-level batches still awaiting dispatch are excluded — see
  `undispatched_summary_by_product/2` for those) so "remaining" always
  means "at a site," regardless of the `site_ids` filter. `total_remaining`
  includes batches dispatched but not yet confirmed received at the site;
  `received_remaining`/`pending_remaining` split that total so callers can
  tell confirmed on-shelf stock apart from in-transit stock. When
  `site_ids` is given, restricts the roll-up to batches at those sites;
  `nil` (the default) means every site in the org.
  """
  def stock_summary_by_product(organization_id, product_ids, site_ids \\ nil) do
    query =
      from(b in Batch,
        where: b.organization_id == ^organization_id,
        where: b.product_id in ^product_ids,
        where: not is_nil(b.site_id),
        group_by: b.product_id,
        select: {
          b.product_id,
          %{
            batch_count: count(b.id),
            total_remaining: coalesce(sum(b.remaining_quantity), 0),
            received_remaining:
              coalesce(
                sum(
                  fragment(
                    "CASE WHEN ? IS NOT NULL THEN ? ELSE 0 END",
                    b.approver_id,
                    b.remaining_quantity
                  )
                ),
                0
              ),
            pending_remaining:
              coalesce(
                sum(
                  fragment(
                    "CASE WHEN ? IS NULL THEN ? ELSE 0 END",
                    b.approver_id,
                    b.remaining_quantity
                  )
                ),
                0
              )
          }
        }
      )

    query
    |> filter_by_site_ids(site_ids)
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Remaining quantity still at the organization, not yet dispatched to a site,
  per product id.
  """
  def undispatched_summary_by_product(organization_id, product_ids) do
    from(b in Batch,
      where: b.organization_id == ^organization_id,
      where: b.product_id in ^product_ids,
      where: is_nil(b.site_id),
      group_by: b.product_id,
      select: {b.product_id, coalesce(sum(b.remaining_quantity), 0)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Count of distinct in-stock batches (remaining_quantity > 0) per product id,
  across the warehouse and every site — the complement count to the unit
  totals from `stock_summary_by_product/3`.
  """
  def batch_counts_by_product(organization_id, product_ids) do
    query =
      from b in Batch,
        where: b.organization_id == ^organization_id,
        where: b.product_id in ^product_ids,
        where: b.remaining_quantity > 0,
        group_by: b.product_id,
        select: {b.product_id, count(b.id)}

    query |> Repo.all() |> Map.new()
  end

  defp filter_by_site_ids(query, nil), do: query
  defp filter_by_site_ids(query, site_ids), do: where(query, [b], b.site_id in ^site_ids)

  @doc """
  Lists org-level batches (received by the organization but not yet
  dispatched to a site) for a product, preloaded with `supplier` (scoped to
  the organization), ordered by soonest expiry.
  """
  def list_undispatched_batches_for_product(organization_id, product_id) do
    supplier_query = from s in Supplier, where: s.organization_id == ^organization_id

    Repo.all(
      from b in Batch,
        where: b.organization_id == ^organization_id,
        where: b.product_id == ^product_id,
        where: is_nil(b.site_id),
        where: b.remaining_quantity > 0,
        order_by: [asc: b.expiry_date],
        preload: [supplier: ^supplier_query]
    )
  end

  @doc """
  Lists all available organization warehouse batches, preloaded with their
  product and supplier, ordered by soonest expiry.
  """
  def list_organization_warehouse_batches(organization_id) do
    product_query = from p in Product, where: p.organization_id == ^organization_id
    supplier_query = from s in Supplier, where: s.organization_id == ^organization_id

    Repo.all(
      from b in Batch,
        where: b.organization_id == ^organization_id,
        where: is_nil(b.site_id),
        where: b.remaining_quantity > 0,
        order_by: [asc: b.expiry_date, asc: b.id],
        preload: [product: ^product_query, supplier: ^supplier_query]
    )
  end

  @doc "Lists batches dispatched to a site but not yet received by staff."
  def list_pending_batches(organization_id) do
    Repo.all(
      from b in Batch,
        where: b.organization_id == ^organization_id,
        where: not is_nil(b.site_id),
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

  @doc "Like `list_active_batches_for_site/2` but also preloads `product` on each batch."
  def list_active_batches_for_site_with_product(organization_id, site_id) do
    product_query = from p in Product, where: p.organization_id == ^organization_id

    Repo.all(
      from b in Batch,
        where: b.organization_id == ^organization_id,
        where: b.site_id == ^site_id,
        where: not is_nil(b.received_at),
        where: not is_nil(b.approver_id),
        where: b.remaining_quantity > 0,
        preload: [product: ^product_query]
    )
  end

  @doc """
  Finds a single active batch at a site by its exact batch/lot number —
  the fallback lookup for a barcode scan whose GTIN segment doesn't match
  any product (e.g. a missing/incorrect product GTIN), used alongside GTIN
  matching rather than instead of it.
  """
  def get_active_batch_by_batch_no(organization_id, site_id, batch_no)
      when is_binary(batch_no) and batch_no != "" do
    Repo.one(
      from b in Batch,
        where: b.organization_id == ^organization_id,
        where: b.site_id == ^site_id,
        where: b.batch_no == ^batch_no,
        where: not is_nil(b.received_at),
        where: not is_nil(b.approver_id),
        where: b.remaining_quantity > 0,
        limit: 1
    )
  end

  def get_active_batch_by_batch_no(_organization_id, _site_id, _batch_no), do: nil

  @doc "Lists active lab-consumable batches at a site with their products preloaded."
  def list_active_lab_consumable_batches_for_site(organization_id, site_id) do
    product_query =
      from p in Product,
        where: p.organization_id == ^organization_id,
        where: p.inventory_type == :lab_consumable

    Repo.all(
      from b in Batch,
        join: p in Product,
        on: p.id == b.product_id,
        where: b.organization_id == ^organization_id,
        where: b.site_id == ^site_id,
        where: p.inventory_type == :lab_consumable,
        where: not is_nil(b.received_at),
        where: not is_nil(b.approver_id),
        where: b.remaining_quantity > 0,
        order_by: [asc: p.generic_name, asc: b.expiry_date],
        preload: [product: ^product_query]
    )
  end

  @doc """
  Lists active (received, approved, in-stock) batches at a site whose
  product has the given `inventory_type`, preloaded with `product`.
  """
  def list_active_batches_for_site_by_inventory_type(organization_id, site_id, inventory_type) do
    product_query =
      from p in Product,
        where: p.organization_id == ^organization_id,
        where: p.inventory_type == ^inventory_type

    Repo.all(
      from b in Batch,
        join: p in Product,
        on: p.id == b.product_id,
        where: b.organization_id == ^organization_id,
        where: b.site_id == ^site_id,
        where: p.inventory_type == ^inventory_type,
        where: not is_nil(b.received_at),
        where: not is_nil(b.approver_id),
        where: b.remaining_quantity > 0,
        order_by: [asc: p.generic_name, asc: b.expiry_date],
        preload: [product: ^product_query]
    )
  end

  @doc """
  True when any received, on-hand lot at the given sites is past its expiry
  date. A lot with no expiry date is not past due.
  """
  def any_expired_on_hand?(organization_id, site_ids, inventory_type)
      when is_list(site_ids) do
    today = Date.utc_today()

    Repo.exists?(
      from b in Batch,
        join: p in Product,
        on: p.id == b.product_id,
        where: b.organization_id == ^organization_id,
        where: b.site_id in ^site_ids,
        where: p.inventory_type == ^inventory_type,
        where: not is_nil(b.received_at),
        where: not is_nil(b.approver_id),
        where: b.remaining_quantity > 0,
        where: b.expiry_date < ^today
    )
  end

  @doc """
  Searches received and approved batches at a site for stock-taking. With a
  blank search, batches with no remaining stock are omitted. A non-blank
  search includes zero-stock batches so unexpected physical stock can be recorded.
  """
  def search_countable_batches_for_site(organization_id, site_id, search, excluded_ids, limit) do
    search = String.trim(search || "")
    product_query = from p in Product, where: p.organization_id == ^organization_id

    query =
      from b in Batch,
        join: p in Product,
        on: p.id == b.product_id,
        where: b.organization_id == ^organization_id,
        where: p.organization_id == ^organization_id,
        where: b.site_id == ^site_id,
        where: not is_nil(b.received_at) and not is_nil(b.approver_id),
        order_by: [asc: p.generic_name, asc: b.batch_no],
        preload: [product: ^product_query]

    query =
      if excluded_ids == [],
        do: query,
        else: where(query, [b, _p], b.id not in ^excluded_ids)

    query =
      if search == "" do
        where(query, [b, _p], b.remaining_quantity > 0)
      else
        pattern = "%#{search}%"

        where(
          query,
          [b, p],
          ilike(p.generic_name, ^pattern) or ilike(p.brand_name, ^pattern) or
            ilike(p.category, ^pattern) or ilike(b.gtin, ^pattern) or
            ilike(b.batch_no, ^pattern)
        )
      end

    query
    |> limit(^limit)
    |> Repo.all()
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

  @doc """
  Lists a product's dispatched (site-bound) batches, preloaded with `site`,
  `approver`, and `supplier` (all scoped to the organization). Org-level
  batches not yet dispatched to a site are excluded — see
  `list_undispatched_batches_for_product/2` for those.
  """
  def list_batches_for_product(organization_id, product_id, site_ids \\ nil) do
    site_query = from s in Site, where: s.organization_id == ^organization_id
    user_query = from u in User, where: u.organization_id == ^organization_id
    supplier_query = from s in Supplier, where: s.organization_id == ^organization_id

    query =
      from(b in Batch,
        where: b.organization_id == ^organization_id,
        where: b.product_id == ^product_id,
        where: not is_nil(b.site_id),
        order_by: [asc: b.expiry_date],
        preload: [site: ^site_query, approver: ^user_query, supplier: ^supplier_query]
      )

    query
    |> filter_by_site_ids(site_ids)
    |> Repo.all()
  end

  @unusable_statuses [:disaggregated, :returned, :expired]

  @doc """
  Batch statuses that never count as usable stock: a shipper retired by
  disaggregation, a lot returned to its supplier, and an expired write-off.
  """
  def unusable_statuses, do: @unusable_statuses

  @doc """
  Whether a batch is usable stock: not in `unusable_statuses/0` and still in
  date. "In date" matches `total_available_stock/3` (expiry after today).
  """
  def usable?(%Batch{status: status, expiry_date: expiry_date}) do
    status not in @unusable_statuses and not is_nil(expiry_date) and
      Date.after?(expiry_date, ThamaniDawa.BusinessDate.today())
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
             where: b.expiry_date > ^ThamaniDawa.BusinessDate.today(),
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

  @doc "Gets a batch only when it belongs to the supplied site."
  def get_batch_for_site!(organization_id, id, site_id) when is_integer(site_id) do
    Repo.get_by!(Batch, id: id, organization_id: organization_id, site_id: site_id)
  end

  def get_batch_for_site!(organization_id, _id, nil) do
    Repo.one!(from b in Batch, where: b.organization_id == ^organization_id and false)
  end

  @doc """
  Gets a single batch scoped to an organization, preloaded with its identity
  (`product`, `site`, `supplier`, `approver`) and prescription and lab usage
  events, each scoped to the same organization. Raises if not found.
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
      goods_receipt: [],
      approver: user_query,
      prescription_batch_dispenses: [
        dispensed_by: user_query,
        prescription_item: [prescription: [patient_visit: :patient]]
      ],
      lab_consumable_usages: [used_by: user_query, lab_order: [patient_visit: :patient]]
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
    |> validate_belongs_to_org(:goods_receipt_id, GoodsReceipt, organization_id)
    |> Repo.audited_insert()
  end

  @doc """
  Receives stock directly into a site's own batches, stamping it as already
  received by `user_id` — for a single-site organization (§5 of project.md),
  where adding stock to the only site that could use it *is* the receipt,
  with no org-level warehouse pool or dispatch step in between.
  """
  def receive_directly_at_site(organization_id, site_id, user_id, attrs)
      when is_integer(organization_id) and is_integer(site_id) do
    attrs =
      attrs
      |> default_remaining_quantity()
      |> Map.put("site_id", site_id)

    %Batch{}
    |> Batch.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Ecto.Changeset.put_change(:received_at, DateTime.truncate(DateTime.utc_now(), :second))
    |> Ecto.Changeset.put_change(:approver_id, user_id)
    |> validate_belongs_to_org(:site_id, Site, organization_id)
    |> validate_belongs_to_org(:product_id, Product, organization_id)
    |> validate_belongs_to_org(:supplier_id, Supplier, organization_id)
    |> Repo.audited_insert()
    |> case do
      {:ok, batch} ->
        Epcis.record_facility_receipt(batch)
        {:ok, batch}

      error ->
        error
    end
  end

  @doc """
  Records a batch as org-level stock — received by the organization but not
  yet assigned to any site. This is the first step of intake; stock becomes
  dispatchable to a site via `dispatch_to_site/2`.
  """
  def receive_into_org_stock(organization_id, attrs) when is_integer(organization_id) do
    %Batch{}
    |> Batch.org_intake_changeset(default_remaining_quantity(attrs))
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> validate_belongs_to_org(:product_id, Product, organization_id)
    |> validate_belongs_to_org(:supplier_id, Supplier, organization_id)
    |> Repo.audited_insert()
  end

  @doc """
  Dispatches an org-level batch (one with no `site_id`) to a site. The
  two-argument form dispatches its full remaining quantity. Use the
  three-argument form to dispatch part of the stock, leaving the balance in
  the organization warehouse for another site.

  Each dispatch creates a separate site `Batch` (pending receipt, as with
  `create_batch/2`) linked back through `source_batch_id`.
  """
  def dispatch_to_site(%Batch{} = org_batch, site_id) when is_integer(site_id) do
    if org_batch.remaining_quantity > 0 do
      dispatch_to_site(org_batch, site_id, org_batch.remaining_quantity)
    else
      {:error, :nothing_to_dispatch}
    end
  end

  def dispatch_to_site(%Batch{}, site_id, quantity)
      when is_integer(site_id) and is_integer(quantity) and quantity <= 0 do
    {:error, :invalid_dispatch_quantity}
  end

  def dispatch_to_site(%Batch{} = org_batch, site_id, quantity)
      when is_integer(site_id) and is_integer(quantity) do
    Repo.transaction(fn -> execute_dispatch(org_batch, site_id, quantity) end)
  end

  defp execute_dispatch(org_batch, site_id, quantity) do
    current_org_batch = lock_source_batch(org_batch)

    with :ok <- validate_dispatch(current_org_batch, quantity),
         {:ok, _} <- debit_org_batch(current_org_batch, quantity),
         {:ok, dispatched} <- create_dispatched_batch(current_org_batch, site_id, quantity) do
      dispatched
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_source_batch(org_batch) do
    Repo.one(
      from b in Batch,
        where: b.id == ^org_batch.id and b.organization_id == ^org_batch.organization_id,
        lock: "FOR UPDATE"
    )
  end

  defp validate_dispatch(nil, _quantity), do: {:error, :not_found}

  defp validate_dispatch(%Batch{site_id: site_id}, _quantity) when not is_nil(site_id),
    do: {:error, :already_dispatched}

  defp validate_dispatch(%Batch{remaining_quantity: remaining}, _quantity) when remaining <= 0,
    do: {:error, :nothing_to_dispatch}

  defp validate_dispatch(%Batch{remaining_quantity: remaining}, quantity)
       when quantity > remaining,
       do: {:error, :insufficient_quantity}

  defp validate_dispatch(_batch, _quantity), do: :ok

  defp debit_org_batch(batch, quantity) do
    set_remaining_quantity(batch, batch.remaining_quantity - quantity)
  end

  # The destination site batch reuses the source lot's `batch_no` verbatim
  # (same physical batch, just delivered in installments), so dispatching
  # the same org batch to the same site more than once — e.g. fulfilling two
  # different requisitions from one warehouse lot — would otherwise collide
  # with `batches_org_product_site_batch_no_index`. Each dispatch must stay
  # its own row (merging into an existing one would re-tag its single
  # `requisition_id`, silently zeroing out whichever requisition it already
  # fulfilled), so disambiguate the batch_no instead.
  defp create_dispatched_batch(batch, site_id, quantity) do
    create_batch(batch.organization_id, %{
      "product_id" => batch.product_id,
      "site_id" => site_id,
      "gtin" => batch.gtin,
      "batch_no" => dispatch_batch_no(batch, site_id),
      "serial" => batch.serial,
      "manufacturer" => batch.manufacturer,
      "manufacture_date" => batch.manufacture_date,
      "expiry_date" => batch.expiry_date,
      "quantity" => quantity,
      "cost_per_unit" => batch.cost_per_unit,
      "supplier_id" => batch.supplier_id,
      "source_batch_id" => batch.id
    })
  end

  @doc """
  Breaks `source_batch` fully into mini-SSCCs for storage. `groups` is a list
  of `%{quantity: pos_integer, serials: [String.t()]}`. Serials are required
  only when the parent still holds serials; a quantity-only parent ignores them.

  Breaking a received shipper SSCC opens that inbound logistic unit, so the
  parent is fully disaggregated: any quantity (and serials) the groups do not
  claim is swept into an auto-generated remainder mini-SSCC, the parent is
  debited to zero and retired to `:disaggregated`, and no stock keeps the
  inbound SSCC. Each child is its own active batch with a freshly minted SSCC,
  linked through `source_batch_id`, copying the parent's goods receipt. A child
  can be re-split later, which retires it in turn.
  """
  def break_into_mini_ssccs(%Batch{} = source_batch, groups, user_id)
      when is_list(groups) and is_integer(user_id) do
    Repo.transaction(fn -> execute_mini_sscc_split(source_batch, groups, user_id) end)
  end

  defp execute_mini_sscc_split(source_batch, groups, user_id) do
    batch = lock_source_batch(source_batch)

    with :ok <- validate_split(batch, groups),
         full_groups = groups_with_remainder(batch, groups),
         {:ok, ssccs} <- mint_ssccs(batch, full_groups),
         {:ok, _} <- retire_source_batch(batch),
         {:ok, children} <- create_mini_sscc_batches(batch, full_groups, ssccs, user_id, nil) do
      Epcis.record_mini_sscc_split(batch, children)
      children
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc """
  Breaks a whole logistic unit (a case/SSCC) into mini-SSCCs. `line_plans` is
  a list of `%{batch_id: id, groups: [%{quantity:, serials:}]}`, one entry per
  contained batch line to break. Each line is fully disaggregated into its own
  single-product child units (one carton + an auto-remainder carton), the
  parent unit is retired to `:disaggregated`, and one consolidated EPCIS
  unpack / pack-per-child / decommission is recorded for the unit's SSCC.
  """
  def break_logistic_unit(%LogisticUnit{} = unit, line_plans, user_id)
      when is_list(line_plans) and is_integer(user_id) do
    Repo.transaction(fn -> execute_logistic_unit_break(unit, line_plans, user_id) end)
  end

  defp execute_logistic_unit_break(unit, line_plans, user_id) do
    locked = lock_logistic_unit(unit)

    with :ok <- validate_unit_break(locked, line_plans),
         {:ok, results} <- disaggregate_lines(locked, line_plans, user_id) do
      emptied? = unit_active_line_count(locked) == 0
      if emptied?, do: {:ok, _} = retire_logistic_unit(locked)
      Epcis.record_logistic_unit_break(locked, results, emptied?)
      results
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp unit_active_line_count(unit) do
    Repo.aggregate(
      from(b in Batch,
        where: b.logistic_unit_id == ^unit.id and b.status == :active and b.remaining_quantity > 0
      ),
      :count
    )
  end

  defp lock_logistic_unit(%LogisticUnit{} = unit) do
    Repo.one(
      from u in LogisticUnit,
        where: u.id == ^unit.id and u.organization_id == ^unit.organization_id,
        lock: "FOR UPDATE"
    )
  end

  defp validate_unit_break(nil, _plans), do: {:error, :not_found}
  defp validate_unit_break(%LogisticUnit{}, []), do: {:error, :no_lines}

  defp validate_unit_break(%LogisticUnit{status: status}, _plans) when status != :active,
    do: {:error, :not_breakable}

  defp validate_unit_break(%LogisticUnit{}, _plans), do: :ok

  defp disaggregate_lines(unit, line_plans, user_id) do
    line_plans
    |> Enum.reduce_while({:ok, []}, fn plan, {:ok, acc} ->
      case disaggregate_line(unit, plan, user_id) do
        {:ok, result} -> {:cont, {:ok, [result | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end

  defp disaggregate_line(unit, %{batch_id: batch_id} = plan, user_id) do
    groups = Map.get(plan, :groups, [])
    line = lock_source_batch(%Batch{id: batch_id, organization_id: unit.organization_id})

    with :ok <- validate_line_in_unit(line, unit),
         :ok <- validate_split(line, groups),
         full_groups = groups_with_remainder(line, groups),
         {:ok, ssccs} <- mint_ssccs(line, full_groups),
         {:ok, _} <- retire_source_batch(line),
         {:ok, children} <- create_mini_sscc_batches(line, full_groups, ssccs, user_id, unit.id) do
      {:ok, %{line: line, children: children}}
    end
  end

  defp validate_line_in_unit(nil, _unit), do: {:error, :line_not_found}

  defp validate_line_in_unit(%Batch{logistic_unit_id: unit_id}, %LogisticUnit{id: id})
       when unit_id != id,
       do: {:error, :line_not_in_unit}

  defp validate_line_in_unit(%Batch{}, _unit), do: :ok

  defp retire_logistic_unit(unit) do
    unit |> Ecto.Changeset.change(status: :disaggregated) |> Repo.update()
  end

  defp validate_split(nil, _groups), do: {:error, :not_found}
  defp validate_split(%Batch{}, []), do: {:error, :no_groups}

  defp validate_split(%Batch{} = batch, groups) when is_list(groups) do
    cond do
      batch.status != :active or batch.remaining_quantity <= 0 ->
        {:error, :not_breakable}

      Enum.any?(groups, &(group_quantity(&1) <= 0)) ->
        {:error, :invalid_group_quantity}

      total_quantity(groups) > batch.remaining_quantity ->
        {:error, :insufficient_quantity}

      batch.serials != [] and not valid_serial_groups?(batch, groups) ->
        {:error, :invalid_serials}

      true ->
        :ok
    end
  end

  # Sweeps whatever the user groups did not claim into one remainder mini-SSCC
  # so the break always consumes the whole parent. Serialized parents assign
  # the leftover serials to the remainder; quantity-only parents carry none.
  defp groups_with_remainder(%Batch{} = batch, groups) do
    remainder = batch.remaining_quantity - total_quantity(groups)

    if remainder > 0 do
      groups ++ [%{quantity: remainder, serials: remainder_serials(batch, groups)}]
    else
      groups
    end
  end

  defp remainder_serials(%Batch{serials: []}, _groups), do: []

  defp remainder_serials(%Batch{serials: serials}, groups) do
    taken = groups |> Enum.flat_map(&group_serials/1) |> MapSet.new()
    Enum.reject(serials, &MapSet.member?(taken, &1))
  end

  # The inbound logistic unit no longer exists once opened: zero the parent,
  # drop its serials (now carried by children), and retire it. Set directly
  # with `change/2` to bypass the user-facing status transition rules.
  defp retire_source_batch(%Batch{} = batch) do
    batch
    |> Ecto.Changeset.change(remaining_quantity: 0, serials: [], status: :disaggregated)
    |> Repo.audited_update()
  end

  defp valid_serial_groups?(batch, groups) do
    serial_lists = Enum.map(groups, &group_serials/1)

    counts_match? =
      Enum.zip(groups, serial_lists)
      |> Enum.all?(fn {group, serials} -> length(serials) == group_quantity(group) end)

    all_serials = List.flatten(serial_lists)

    counts_match? and
      all_serials == Enum.uniq(all_serials) and
      Enum.all?(all_serials, &is_binary/1) and
      Enum.all?(all_serials, &(&1 in batch.serials))
  end

  defp group_quantity(%{quantity: quantity}) when is_integer(quantity), do: quantity
  defp group_quantity(_group), do: 0

  defp group_serials(group) do
    group
    |> Map.get(:serials, [])
    |> List.wrap()
  end

  defp total_quantity(groups) do
    Enum.reduce(groups, 0, fn group, total -> total + max(group_quantity(group), 0) end)
  end

  # One member-API SSCC per carton. The batch number sent to GS1 is the
  # source lot: that is the batch `get_sscc_contents` uses to find serials.
  defp mint_ssccs(batch, groups) do
    batch = Repo.preload(batch, :site)

    groups
    |> Enum.reduce_while({:ok, []}, fn group, {:ok, acc} ->
      case MemberApi.create_sscc(mini_sscc_request(batch, group),
             api_token: ThamaniDawa.Organizations.gs1_api_key(batch.organization_id)
           ) do
        {:ok, sscc} -> {:cont, {:ok, [sscc | acc]}}
        {:error, reason} -> {:halt, {:error, {:gs1, reason}}}
      end
    end)
    |> case do
      {:ok, ssccs} -> {:ok, Enum.reverse(ssccs)}
      error -> error
    end
  end

  defp mini_sscc_request(batch, group) do
    site = batch.site
    location = if(site, do: site.address || site.name, else: nil)

    %{
      "batch_info" => [
        %{
          "gtin" => batch.gtin,
          "batch" => batch.batch_no,
          "production_date" => iso_date(batch.manufacture_date),
          "expiry_date" => iso_date(batch.expiry_date)
        }
      ],
      "address" => %{
        "from_address" => location || "N/A",
        "to_address" => location || "N/A"
      },
      "facility_gln" => site && site.gln,
      "count_of_trade_items" => group_quantity(group),
      "material_description" => batch.batch_no
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp iso_date(%Date{} = date), do: Date.to_iso8601(date)
  defp iso_date(_date), do: nil

  defp create_mini_sscc_batches(batch, groups, ssccs, user_id, parent_unit_id) do
    # Count existing children once. A remainder can be split again later, and
    # querying inside the loop would see siblings inserted earlier in this
    # same transaction and skip suffixes.
    offset = count_mini_sscc_children(batch)

    groups
    |> Enum.zip(ssccs)
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {{group, sscc}, n}, {:ok, acc} ->
      serials = if batch.serials == [], do: [], else: group_serials(group)

      with {:ok, unit} <- create_child_logistic_unit(batch, sscc, parent_unit_id),
           {:ok, child} <-
             create_batch(batch.organization_id, %{
               "product_id" => batch.product_id,
               "site_id" => batch.site_id,
               "gtin" => batch.gtin,
               "batch_no" => mini_sscc_batch_no(batch, offset + n),
               "sscc" => sscc,
               "logistic_unit_id" => unit.id,
               "serials" => serials,
               "manufacturer" => batch.manufacturer,
               "manufacture_date" => batch.manufacture_date,
               "expiry_date" => batch.expiry_date,
               "quantity" => group.quantity,
               "cost_per_unit" => batch.cost_per_unit,
               "supplier_id" => batch.supplier_id,
               "goods_receipt_id" => batch.goods_receipt_id,
               "source_batch_id" => batch.id
             }),
           {:ok, stored} <- putaway(child, %{"zone" => :storage}),
           {:ok, received} <- receive_batch(stored, user_id) do
        {:cont, {:ok, [received | acc]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, children} -> {:ok, Enum.reverse(children)}
      error -> error
    end
  end

  # Each mini-SSCC carton is its own single-product logistic unit, minted from
  # the parent case (`parent_unit_id`, nil when casing loose stock).
  defp create_child_logistic_unit(batch, sscc, parent_unit_id) do
    %LogisticUnit{}
    |> LogisticUnit.changeset(%{
      organization_id: batch.organization_id,
      sscc: sscc,
      kind: :case,
      source: :minted,
      site_id: batch.site_id,
      goods_receipt_id: batch.goods_receipt_id,
      parent_logistic_unit_id: parent_unit_id
    })
    |> Repo.insert()
  end

  defp count_mini_sscc_children(batch) do
    Repo.aggregate(
      from(b in Batch,
        where: b.organization_id == ^batch.organization_id,
        where: b.source_batch_id == ^batch.id
      ),
      :count
    )
  end

  # `n` is the 1-based index within this call, plus how many mini-SSCCs this
  # parent already has. Splitting LOT123 yields LOT123-S1, then LOT123-S2.
  # Splitting LOT123-S1 again yields LOT123-S1-S1.
  defp mini_sscc_batch_no(batch, n) do
    "#{batch.batch_no}-S#{n}"
  end

  defp dispatch_batch_no(batch, site_id) do
    prior_dispatches =
      Repo.aggregate(
        from(b in Batch,
          where: b.organization_id == ^batch.organization_id,
          where: b.site_id == ^site_id,
          where: b.source_batch_id == ^batch.id
        ),
        :count
      )

    if prior_dispatches == 0 do
      batch.batch_no
    else
      "#{batch.batch_no}-D#{prior_dispatches + 1}"
    end
  end

  @doc """
  Marks a batch as received by `user_id`, stamping `approver_id`/`received_at`
  and making it active for dispensing or lab consumption. Pass a `"quantity"`
  in `attrs` when the amount actually received differs from what was
  dispatched — `remaining_quantity` is reset to match, since a pending batch
  can't yet have anything dispensed from it.
  """
  def receive_batch(%Batch{} = batch, user_id, attrs \\ %{}) do
    was_pending = is_nil(batch.received_at)

    attrs =
      Map.merge(attrs, %{
        "received_at" => DateTime.utc_now(),
        "approver_id" => user_id
      })

    case batch
         |> Batch.receive_changeset(attrs)
         |> Repo.audited_update() do
      {:ok, received} ->
        if was_pending, do: Epcis.record_facility_receipt(received)
        {:ok, received}

      error ->
        error
    end
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
        where: b.status == :active,
        where: b.remaining_quantity > 0,
        where: not is_nil(b.approver_id),
        where: b.expiry_date > ^ThamaniDawa.BusinessDate.today(),
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
        where: b.status == :active,
        where: b.remaining_quantity > 0,
        where: not is_nil(b.approver_id),
        where: b.expiry_date > ^ThamaniDawa.BusinessDate.today(),
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
  dispensing, lab consumption, or a distributor shipment approval. Returns
  `{:error, changeset}` if that would take it below zero.
  """
  def decrement_remaining_quantity(%Batch{} = batch, quantity)
      when is_integer(quantity) and quantity > 0 do
    batch
    |> Ecto.Changeset.change(remaining_quantity: batch.remaining_quantity - quantity)
    |> Ecto.Changeset.validate_number(:remaining_quantity, greater_than_or_equal_to: 0)
    |> Repo.audited_update()
  end

  @doc """
  Sets `remaining_quantity` directly to `quantity`, for inventory movements
  that update a known absolute balance rather than decrementing a usage amount.
  """
  def set_remaining_quantity(%Batch{} = batch, quantity) when is_integer(quantity) do
    batch
    |> Ecto.Changeset.change(remaining_quantity: quantity)
    |> Ecto.Changeset.validate_number(:remaining_quantity, greater_than_or_equal_to: 0)
    |> Repo.audited_update()
  end

  @doc """
  Lists batches currently located at a site, newest-received batches first,
  for the warehouse-contents view. Preloads `product`.
  """
  def list_batches_for_site(organization_id, site_id) do
    product_query = from p in Product, where: p.organization_id == ^organization_id

    Repo.all(
      from b in Batch,
        where: b.organization_id == ^organization_id,
        where: b.site_id == ^site_id,
        order_by: [asc: b.zone, asc: b.bin, asc: b.expiry_date],
        preload: [product: ^product_query]
    )
  end

  @doc """
  Every batch held at one of `site_ids`, with its product, site and supplier
  preloaded, soonest expiry first. Feeds the read-only site stock pages
  (`/lab/stock`, `/pharmacy/stock`), which roll batches up by product and
  filter in memory; an empty `site_ids` returns no batches.
  """
  def list_site_stock(_organization_id, []), do: []

  def list_site_stock(organization_id, site_ids) when is_list(site_ids) do
    product_query = from p in Product, where: p.organization_id == ^organization_id

    Repo.all(
      from b in Batch,
        where: b.organization_id == ^organization_id,
        where: b.site_id in ^site_ids,
        order_by: [asc: b.expiry_date, asc: b.id],
        preload: [:site, :supplier, product: ^product_query]
    )
  end

  @doc """
  Lists every batch across every site in an organization, for the
  warehouse-contents view when the viewer (an org admin) has no single
  current site. Preloads `product`.
  """
  def list_batches_for_organization(organization_id) do
    product_query = from p in Product, where: p.organization_id == ^organization_id

    Repo.all(
      from b in Batch,
        where: b.organization_id == ^organization_id,
        order_by: [asc: b.zone, asc: b.bin, asc: b.expiry_date],
        preload: [:site, product: ^product_query]
    )
  end

  @doc """
  Every outbound shipment that drew units from this batch, newest first,
  with the count of scanned units each one took — the "where did it go"
  half of a batch's trail, alongside its `goods_receipt` association for
  "where did it come from". Returns `%{shipment: shipment, unit_count: n}`.
  """
  def list_shipments_from_batch(%Batch{} = batch) do
    Repo.all(
      from si in ShipmentItem,
        join: s in Shipment,
        on: s.id == si.shipment_id,
        where: si.batch_id == ^batch.id,
        group_by: s.id,
        order_by: [desc: s.id],
        select: %{shipment_id: s.id, unit_count: count(si.id)}
    )
    |> Enum.map(fn %{shipment_id: shipment_id, unit_count: unit_count} ->
      %{shipment: Repo.get!(Shipment, shipment_id), unit_count: unit_count}
    end)
  end

  @doc """
  Puts away a batch into a zone (and optional bin) — an intra-warehouse
  move, never EPCIS-reportable. Typically `:storage` or `:quarantine` from
  `:receiving`, but any zone move is accepted (see also `relocate/3`, the
  bin-to-bin shortcut used from the Stock view).
  """
  def putaway(%Batch{} = batch, attrs) do
    batch
    |> Batch.location_changeset(attrs)
    |> Repo.audited_update()
  end

  @doc "Bin-to-bin (or zone-to-zone) relocation within a site. Alias of `putaway/2`."
  def relocate(%Batch{} = batch, attrs), do: putaway(batch, attrs)

  defp transition_status(%Batch{} = batch, new_status, build_event) do
    batch
    |> Batch.status_changeset(new_status)
    |> Repo.audited_update()
    |> case do
      {:ok, updated} ->
        build_event.(updated)
        {:ok, updated}

      error ->
        error
    end
  end

  @doc "Marks a batch damaged (§4.4.1). May start from `:active` or `:quarantined`."
  def mark_damaged(%Batch{} = batch, reference, _user)
      when is_binary(reference) and reference != "" do
    transition_status(
      batch,
      :damaged,
      &Epcis.record_batch_status(&1, "damaged", "inspecting", "damaged", reference, "incident")
    )
  end

  @doc """
  Marks a batch expired (§4.4.2.1). Manually triggered per batch — the
  platform does not auto-create expiry events from the passage of time.
  """
  def mark_expired(%Batch{} = batch, _user) do
    transition_status(
      batch,
      :expired,
      &Epcis.record_batch_status(&1, "expired", "inspecting", "expired", nil, nil)
    )
  end

  @doc "Marks a batch stolen (§4.4.2.2). Terminal."
  def mark_stolen(%Batch{} = batch, reference, _user)
      when is_binary(reference) and reference != "" do
    transition_status(
      batch,
      :stolen,
      &Epcis.record_batch_status(&1, "stolen", "decommissioning", "stolen", reference, "incident")
    )
  end

  @doc "Marks a batch lost (§4.4.2.2)."
  def mark_lost(%Batch{} = batch, reference, _user)
      when is_binary(reference) and reference != "" do
    transition_status(
      batch,
      :inactive,
      &Epcis.record_batch_status(&1, "lost", "decommissioning", "inactive", reference, "incident")
    )
  end

  @doc "Marks a batch exported out of the PPB-tracked supply chain (§4.4.4)."
  def mark_exported(%Batch{} = batch, reference, _user)
      when is_binary(reference) and reference != "" do
    transition_status(
      batch,
      :non_sellable_other,
      &Epcis.record_batch_status(
        &1,
        "exported",
        "decommissioning",
        "non_sellable_other",
        reference,
        "export"
      )
    )
  end

  @doc """
  Marks a batch recalled (§4.3.1). Regulator-driven in principle — this
  platform has no inbound PPB channel to learn of a recall automatically,
  so this is necessarily an internal, admin-triggered action taken on a
  recall notice received outside this system. Overrides any prior state
  except `:destroyed`.
  """
  def mark_recalled(%Batch{} = batch, reference, _user)
      when is_binary(reference) and reference != "" do
    transition_status(
      batch,
      :recalled,
      &Epcis.record_batch_status(&1, "recalled", "holding", "recalled", reference, "recall")
    )
  end

  @doc """
  Marks a batch returned to its supplier. Only legal from `:active`.
  `reference` is the return/credit-note reference.
  """
  def mark_returned(%Batch{} = batch, reference, _user)
      when is_binary(reference) and reference != "" do
    transition_status(
      batch,
      :returned,
      &Epcis.record_batch_status(&1, "returned", "returning", "returned", reference, "return")
    )
  end

  @doc """
  Marks a batch destroyed (§4.3.2). Only legal from `:damaged`, `:expired`,
  or `:recalled`. Terminal.
  """
  def mark_destroyed(%Batch{} = batch, reference, _user)
      when is_binary(reference) and reference != "" do
    transition_status(
      batch,
      :destroyed,
      &Epcis.record_batch_status(
        &1,
        "destroyed",
        "destroying",
        "destroyed",
        reference,
        "destruction"
      )
    )
  end
end
