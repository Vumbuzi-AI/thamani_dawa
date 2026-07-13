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

  @doc "Lists an organization's batches."
  def list_batches(organization_id) do
    Repo.all(from b in Batch, where: b.organization_id == ^organization_id)
  end

  @doc "Gets a single batch scoped to an organization. Raises if not found."
  def get_batch!(organization_id, id) do
    Repo.get_by!(Batch, id: id, organization_id: organization_id)
  end

  @doc """
  Creates a batch under the given organization. When `remaining_quantity` is
  omitted, it defaults to `quantity` — a freshly received batch starts fully
  stocked.
  """
  def create_batch(organization_id, attrs) when is_integer(organization_id) do
    %Batch{}
    |> Batch.changeset(default_remaining_quantity(attrs))
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> validate_belongs_to_org(:site_id, Site, organization_id)
    |> validate_belongs_to_org(:product_id, Product, organization_id)
    |> Repo.insert()
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

    quantity = Map.get(attrs, :quantity) || Map.get(attrs, "quantity")

    if has_remaining? or is_nil(quantity) do
      attrs
    else
      Map.put(attrs, :remaining_quantity, quantity)
    end
  end

  @doc """
  Picks the batch to dispense/consume from at `site_id` for `product_id`,
  per FEFO (first-expired-first-out, §9): the active batch with stock
  remaining, soonest expiry first. This query is what enforces §4.3's
  "batch must be at the prescription's own site_id" for pharmacy dispensing
  — a batch at any other site is never a candidate.

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
