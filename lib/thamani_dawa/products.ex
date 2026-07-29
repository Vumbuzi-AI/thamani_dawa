defmodule ThamaniDawa.Products do
  @moduledoc """
  The product catalog (§4.1). Every product belongs to exactly one
  organization — two pharmacies can stock the same GTIN without conflict,
  since uniqueness is scoped per-organization, not global (§2.2).
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.Repo

  @doc "Lists an organization's products."
  def list_products(organization_id) do
    Repo.all(
      from p in Product, where: p.organization_id == ^organization_id, order_by: [asc: p.id]
    )
  end

  @doc "Lists products that have batches at specific sites with pagination and optional search filter."
  def list_products_with_site_batches_paginated(organization_id, site_ids, page \\ 1, opts \\ []) do
    if is_list(site_ids) and site_ids != [] do
      search = Keyword.get(opts, :search)

      query =
        from(p in Product,
          join: b in ThamaniDawa.Batches.Batch,
          on: b.product_id == p.id,
          where: p.organization_id == ^organization_id,
          where: b.site_id in ^site_ids,
          distinct: true,
          order_by: [asc: p.id]
        )

      query = filter_search(query, search)
      Repo.paginate(query, page: page)
    else
      from(p in Product, where: false)
      |> Repo.paginate(page: page)
    end
  end

  def list_products_paginated(organization_id, page \\ 1, opts \\ []) do
    from(p in Product, where: p.organization_id == ^organization_id, order_by: [asc: p.id])
    |> filter_search(Keyword.get(opts, :search))
    |> filter_category(Keyword.get(opts, :category))
    |> filter_flag(:is_otc, Keyword.get(opts, :is_otc))
    |> filter_flag(:is_dangerous_drug, Keyword.get(opts, :is_dangerous_drug))
    |> Repo.paginate(page: page)
  end

  defp filter_search(query, search) when is_binary(search) do
    search = String.trim(search)

    if search != "" do
      pattern = "%#{search}%"

      from(p in query,
        where:
          ilike(p.generic_name, ^pattern) or
            ilike(p.brand_name, ^pattern) or
            ilike(p.gtin, ^pattern) or
            ilike(p.category, ^pattern)
      )
    else
      query
    end
  end

  defp filter_search(query, _search), do: query

  defp filter_category(query, category) when is_binary(category) do
    category = String.trim(category)
    if category != "", do: from(p in query, where: p.category == ^category), else: query
  end

  defp filter_category(query, _category), do: query

  defp filter_flag(query, :is_otc, true), do: from(p in query, where: p.is_otc == true)

  defp filter_flag(query, :is_dangerous_drug, true),
    do: from(p in query, where: p.is_dangerous_drug == true)

  defp filter_flag(query, _field, _val), do: query

  @doc "Lists products that have active, approved batches at a site."
  def list_active_products_for_site(organization_id, site_id) do
    Repo.all(
      from p in Product,
        join: b in ThamaniDawa.Batches.Batch,
        on: b.product_id == p.id,
        where: p.organization_id == ^organization_id,
        where: b.site_id == ^site_id,
        where: not is_nil(b.received_at),
        where: not is_nil(b.approver_id),
        where: b.remaining_quantity > 0,
        distinct: p.id
    )
  end

  @doc """
  Lists products with active, approved batches at a site, each annotated
  with its `stock` — the total `remaining_quantity` across those batches —
  so the prescriber can see what's actually available at their site.
  """
  def list_active_products_with_stock_for_site(organization_id, site_id) do
    Repo.all(
      from p in Product,
        join: b in ThamaniDawa.Batches.Batch,
        on: b.product_id == p.id,
        where: p.organization_id == ^organization_id,
        where: b.site_id == ^site_id,
        where: not is_nil(b.received_at),
        where: not is_nil(b.approver_id),
        where: b.remaining_quantity > 0,
        group_by: p.id,
        order_by: p.generic_name,
        select: %{
          id: p.id,
          generic_name: p.generic_name,
          brand_name: p.brand_name,
          price: p.price,
          stock: sum(b.remaining_quantity)
        }
    )
  end

  @doc "Gets a single product scoped to an organization. Raises if not found."
  def get_product!(organization_id, id) do
    Repo.get_by!(Product, id: id, organization_id: organization_id)
  end

  @doc "Creates a product under the given organization."
  def create_product(organization_id, attrs) when is_integer(organization_id) do
    %Product{}
    |> Product.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.insert()
  end

  @doc "Updates a product."
  def update_product(%Product{} = product, attrs) do
    product
    |> Product.changeset(attrs)
    |> Repo.update()
  end
end
