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
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Requisitions.Requisition
  alias ThamaniDawa.Requisitions.RequisitionFulfillment
  alias ThamaniDawa.Requisitions.RequisitionLine
  alias ThamaniDawa.Sites.Site

  @doc "Lists all requisitions for an organization, newest first, with lines and their products preloaded."
  def list_requisitions(organization_id) do
    Repo.all(
      from r in Requisition,
        where: r.organization_id == ^organization_id,
        order_by: [desc: r.inserted_at],
        preload: [lines: :product]
    )
  end

  @tab_groups %{
    "pending" => [:pending],
    "approved" => [:approved, :partially_approved],
    "fulfilled" => [:partially_fulfilled, :fulfilled],
    "rejected" => [:rejected, :cancelled]
  }

  @doc "The status tabs for a requisition list, in display order."
  def tabs,
    do: [
      {"pending", "Pending"},
      {"approved", "Approved"},
      {"fulfilled", "Fulfilled"},
      {"rejected", "Rejected"}
    ]

  @doc "Counts `requisitions` (already fetched/scoped) into each tab, for tab badges."
  def tab_counts(requisitions) do
    Map.new(@tab_groups, fn {tab, statuses} ->
      {tab, Enum.count(requisitions, &(&1.status in statuses))}
    end)
  end

  @doc "Filters an in-memory list of requisitions down to one status tab. `\"all\"` or an unknown tab returns every requisition."
  def filter_by_tab(requisitions, tab) do
    case Map.get(@tab_groups, tab) do
      nil -> requisitions
      statuses -> Enum.filter(requisitions, &(&1.status in statuses))
    end
  end

  @doc "Filters an in-memory list of requisitions to those raised on or between `date_from`/`date_to` (either may be `nil`)."
  def filter_by_date_range(requisitions, nil, nil), do: requisitions

  def filter_by_date_range(requisitions, date_from, date_to) do
    Enum.filter(requisitions, fn r ->
      date = DateTime.to_date(r.inserted_at)

      (is_nil(date_from) or Date.compare(date, date_from) != :lt) and
        (is_nil(date_to) or Date.compare(date, date_to) != :gt)
    end)
  end

  @doc "Filters an in-memory list of requisitions by reference number (case-insensitive substring match)."
  def filter_by_search(requisitions, term) when term in [nil, ""], do: requisitions

  def filter_by_search(requisitions, term) do
    needle = String.downcase(term)
    Enum.filter(requisitions, &String.contains?(String.downcase(&1.number), needle))
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
    |> Repo.preload([
      :product,
      :site,
      :requested_by,
      :reviewed_by,
      lines: [:product, :fulfillments]
    ])
  end

  @doc "Creates a header and its unique-product lines atomically."
  def create_multi_requisition(organization_id, requested_by_id, attrs)
      when is_integer(organization_id) and is_integer(requested_by_id) do
    lines = extract_lines(attrs)

    case validate_lines(lines) do
      :ok -> insert_requisition_with_lines(organization_id, requested_by_id, attrs, lines)
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_lines(attrs) do
    line_attrs = Map.get(attrs, "lines") || Map.get(attrs, :lines) || %{}
    if is_map(line_attrs), do: Map.values(line_attrs), else: line_attrs
  end

  defp validate_lines(lines) do
    products = Enum.map(lines, &(Map.get(&1, "product_id") || Map.get(&1, :product_id)))

    cond do
      lines == [] -> {:error, :no_lines}
      length(products) != length(Enum.uniq(products)) -> {:error, :duplicate_products}
      true -> :ok
    end
  end

  defp insert_requisition_with_lines(organization_id, requested_by_id, attrs, lines) do
    result =
      Repo.transaction(fn ->
        requisition = insert_header!(organization_id, requested_by_id, attrs)
        insert_lines!(lines, requisition, organization_id)
        Repo.preload(requisition, [:lines])
      end)

    case result do
      {:ok, requisition} -> {:ok, requisition}
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_header!(organization_id, requested_by_id, attrs) do
    changeset =
      %Requisition{}
      |> Requisition.header_changeset(put_number(attrs, organization_id))
      |> Ecto.Changeset.put_change(:organization_id, organization_id)
      |> Ecto.Changeset.put_change(:requested_by_id, requested_by_id)
      |> validate_belongs_to_org(:site_id, Site, organization_id)
      |> validate_belongs_to_org(:requested_by_id, User, organization_id)

    if not changeset.valid?, do: Repo.rollback(changeset)

    header = Ecto.Changeset.delete_change(changeset, :lines)
    {:ok, requisition} = Repo.audited_insert(header)
    requisition
  end

  defp insert_lines!(lines, requisition, organization_id) do
    Enum.each(lines, fn attrs ->
      line_changeset =
        attrs
        |> normalize_line_attrs()
        |> then(&RequisitionLine.changeset(%RequisitionLine{}, &1))
        |> Ecto.Changeset.put_change(:requisition_id, requisition.id)
        |> Ecto.Changeset.put_change(:organization_id, organization_id)
        |> validate_belongs_to_org(:product_id, Product, organization_id)

      if not line_changeset.valid?, do: Repo.rollback(line_changeset)

      case Repo.audited_insert(line_changeset) do
        {:ok, _line} -> :ok
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp normalize_line_attrs(attrs) do
    Map.new([{"product_id", :product_id}, {"requested_quantity", :requested_quantity}], fn {key,
                                                                                            atom} ->
      {atom, Map.get(attrs, key) || Map.get(attrs, atom)}
    end)
  end

  @doc "Applies independent approved quantities to every line in one locked review transaction."
  def review_lines(organization_id, requisition_id, reviewer_id, decisions)
      when is_map(decisions) do
    with :ok <- validate_user_organization(organization_id, reviewer_id) do
      Repo.transaction(fn ->
        do_review_lines(organization_id, requisition_id, reviewer_id, decisions)
      end)
    end
  end

  defp do_review_lines(organization_id, requisition_id, reviewer_id, decisions) do
    requisition =
      Repo.one(
        from r in Requisition,
          where: r.id == ^requisition_id and r.organization_id == ^organization_id,
          lock: "FOR UPDATE"
      )

    if is_nil(requisition) or requisition.status != :pending, do: Repo.rollback(:not_pending)

    lines =
      Repo.all(
        from l in RequisitionLine,
          where: l.requisition_id == ^requisition_id,
          lock: "FOR UPDATE"
      )

    if lines == [], do: Repo.rollback(:no_lines)

    Enum.each(lines, &apply_line_decision!(&1, decisions, reviewer_id))

    update_header_status(requisition_id)
  end

  defp apply_line_decision!(line, decisions, reviewer_id) do
    amount =
      decisions
      |> Map.get(to_string(line.id), Map.get(decisions, line.id))
      |> parse_decision_amount()

    if not is_integer(amount) or amount < 0 or amount > line.requested_quantity,
      do: Repo.rollback(:invalid_approved_quantity)

    status =
      cond do
        amount == 0 -> :rejected
        amount < line.requested_quantity -> :partially_approved
        true -> :approved
      end

    line
    |> Ecto.Changeset.change(
      status: status,
      approved_quantity: amount,
      reviewed_by_id: reviewer_id,
      reviewed_at: now()
    )
    |> update_or_rollback()
  end

  defp parse_decision_amount(amount) when is_binary(amount) do
    case Integer.parse(amount) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp parse_decision_amount(amount), do: amount

  defp update_header_status(requisition_id) do
    requisition = Repo.get!(Requisition, requisition_id)
    lines = Repo.all(from l in RequisitionLine, where: l.requisition_id == ^requisition_id)
    approved = Enum.sum(Enum.map(lines, &(&1.approved_quantity || 0)))
    requested = Enum.sum(Enum.map(lines, & &1.requested_quantity))

    fulfilled =
      Repo.one(
        from f in RequisitionFulfillment,
          join: l in RequisitionLine,
          on: f.requisition_line_id == l.id,
          where: l.requisition_id == ^requisition_id,
          select: coalesce(sum(f.dispatched_quantity), 0)
      )

    status =
      cond do
        fulfilled > 0 and fulfilled >= approved -> :fulfilled
        fulfilled > 0 -> :partially_fulfilled
        approved == 0 -> :rejected
        approved < requested -> :partially_approved
        true -> :approved
      end

    requisition |> Ecto.Changeset.change(status: status) |> Repo.audited_update!()
  end

  @doc "Dispatches stock for a single approved line and records the dispatch atomically."
  def fulfill_requisition_line(
        organization_id,
        line_id,
        %Batch{} = org_batch,
        quantity,
        actor_id \\ nil
      ) do
    Repo.transaction(fn ->
      fulfill_line_locked(organization_id, line_id, org_batch, quantity, actor_id)
    end)
  end

  @doc "Atomically dispatches stock for several approved lines in one requisition."
  def fulfill_requisition_lines(organization_id, dispatches, actor_id) when is_list(dispatches) do
    Repo.transaction(fn ->
      Enum.each(dispatches, fn {line_id, %Batch{} = batch, quantity} ->
        fulfill_line_locked(organization_id, line_id, batch, quantity, actor_id)
      end)
    end)
  end

  defp fulfill_line_locked(organization_id, line_id, org_batch, quantity, actor_id) do
    with {:ok, line} <- lock_approved_line(organization_id, line_id),
         {:ok, batch} <- get_organization_warehouse_batch(organization_id, org_batch.id),
         :ok <- validate_line_dispatch(line, batch, quantity) do
      dispatch_line!(line, batch, quantity, actor_id, organization_id)
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_approved_line(organization_id, line_id) do
    line =
      Repo.one(
        from l in RequisitionLine,
          join: r in Requisition,
          on: r.id == l.requisition_id,
          where:
            l.id == ^line_id and l.organization_id == ^organization_id and
              r.organization_id == ^organization_id,
          lock: "FOR UPDATE"
      )

    if is_nil(line) or is_nil(line.approved_quantity) or line.approved_quantity == 0 do
      {:error, :not_approved}
    else
      {:ok, line}
    end
  end

  defp get_organization_warehouse_batch(organization_id, batch_id) do
    case Repo.get_by(Batch, id: batch_id, organization_id: organization_id) do
      %Batch{site_id: nil} = batch -> {:ok, batch}
      _not_a_warehouse_batch -> {:error, :batch_not_found}
    end
  end

  defp validate_line_dispatch(line, batch, quantity) do
    cond do
      batch.product_id != line.product_id ->
        {:error, :product_mismatch}

      not is_integer(quantity) or quantity <= 0 ->
        {:error, :invalid_dispatch_quantity}

      quantity > line.approved_quantity - dispatched_so_far(line.id) ->
        {:error, :exceeds_approved_quantity}

      true ->
        :ok
    end
  end

  defp dispatched_so_far(line_id) do
    Repo.one(
      from f in RequisitionFulfillment,
        where: f.requisition_line_id == ^line_id,
        select: coalesce(sum(f.dispatched_quantity), 0)
    )
  end

  defp dispatch_line!(line, batch, quantity, actor_id, organization_id) do
    requisition = Repo.get!(Requisition, line.requisition_id)
    {:ok, dispatched} = ThamaniDawa.Batches.dispatch_to_site(batch, requisition.site_id, quantity)
    {:ok, tagged} = tag_requisition(dispatched, requisition.id)

    attrs = %{
      requisition_line_id: line.id,
      organization_id: organization_id,
      source_batch_id: batch.id,
      dispatched_batch_id: tagged.id,
      dispatched_quantity: quantity,
      dispatched_by_id: actor_id
    }

    case %RequisitionFulfillment{}
         |> RequisitionFulfillment.changeset(attrs)
         |> Repo.audited_insert() do
      {:ok, _} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end

    update_line_fulfillment_status(line)
    update_header_status(requisition.id)
  end

  defp update_line_fulfillment_status(line) do
    dispatched =
      Repo.one(
        from f in RequisitionFulfillment,
          where: f.requisition_line_id == ^line.id,
          select: coalesce(sum(f.dispatched_quantity), 0)
      )

    status = if dispatched >= line.approved_quantity, do: :fulfilled, else: :partially_fulfilled
    line |> Ecto.Changeset.change(status: status) |> Repo.audited_update!()
  end

  @doc "Returns a changeset for building or validating a requisition form."
  def change_requisition(%Requisition{} = requisition, attrs \\ %{}) do
    Requisition.create_changeset(requisition, attrs)
  end

  @doc """
  Creates a requisition for a site. `attrs` must include `site_id`,
  `product_id`, and `quantity`; `notes` is optional.
  `organization_id`/`requested_by_id` come from the caller's scope, not attrs.
  """
  def create_requisition(organization_id, requested_by_id, attrs)
      when is_integer(organization_id) and is_integer(requested_by_id) do
    Repo.transaction(fn ->
      changeset =
        %Requisition{}
        |> Requisition.create_changeset(put_number(attrs, organization_id))
        |> Ecto.Changeset.put_change(:organization_id, organization_id)
        |> Ecto.Changeset.put_change(:requested_by_id, requested_by_id)
        |> validate_belongs_to_org(:site_id, Site, organization_id)
        |> validate_belongs_to_org(:product_id, Product, organization_id)
        |> validate_belongs_to_org(:requested_by_id, User, organization_id)

      case Repo.audited_insert(changeset) do
        {:ok, requisition} -> requisition
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
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
    reviewed =
      locked
      |> Requisition.review_changeset(%{
        status: :approved,
        reviewed_by_id: reviewer_id,
        reviewed_at: DateTime.utc_now(),
        needs_reorder: needs_reorder?(organization_id, locked.product_id, locked.quantity)
      })
      |> update_or_rollback()

    approve_lines(reviewed, reviewer_id)
  end

  defp approve_lines(reviewed, reviewer_id) do
    lines =
      Repo.all(
        from l in RequisitionLine, where: l.requisition_id == ^reviewed.id, lock: "FOR UPDATE"
      )

    if lines == [] do
      reviewed
    else
      Enum.each(lines, &approve_line!(&1, reviewer_id))
      update_header_status(reviewed.id)
    end
  end

  defp approve_line!(line, reviewer_id) do
    line
    |> Ecto.Changeset.change(
      status: :approved,
      approved_quantity: line.requested_quantity,
      reviewed_by_id: reviewer_id,
      reviewed_at: now()
    )
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
    rejected =
      locked
      |> Requisition.review_changeset(%{
        status: :rejected,
        reviewed_by_id: reviewer_id,
        reviewed_at: DateTime.utc_now(),
        rejection_reason: rejection_reason
      })
      |> update_or_rollback()

    reject_lines(rejected.id, reviewer_id)
    rejected
  end

  defp reject_lines(requisition_id, reviewer_id) do
    lines = Repo.all(from l in RequisitionLine, where: l.requisition_id == ^requisition_id)

    Enum.each(lines, fn line ->
      line
      |> Ecto.Changeset.change(
        status: :rejected,
        approved_quantity: 0,
        reviewed_by_id: reviewer_id,
        reviewed_at: now()
      )
      |> update_or_rollback()
    end)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

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

  defp next_number!(organization_id) do
    {1, _} =
      Repo.update_all(
        from(o in Organization, where: o.id == ^organization_id),
        inc: [next_requisition_number: 1]
      )

    organization = Repo.get!(Organization, organization_id)
    "REQ-" <> String.pad_leading(Integer.to_string(organization.next_requisition_number), 6, "0")
  end

  defp put_number(attrs, organization_id) do
    number = next_number!(organization_id)

    if Enum.any?(Map.keys(attrs), &is_binary/1) do
      Map.put(attrs, "number", number)
    else
      Map.put(attrs, :number, number)
    end
  end
end
