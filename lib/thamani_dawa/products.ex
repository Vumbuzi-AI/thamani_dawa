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

  @doc "Gets an organization's product by normalized GTIN, or nil."
  def get_product_by_gtin(organization_id, gtin) when is_binary(gtin) do
    Repo.get_by(Product, organization_id: organization_id, gtin: gtin)
  end

  @doc """
  Lists products that have any batch — dispatched or still awaiting
  dispatch — with pagination and optional search filter. `site_ids: nil`
  means unrestricted (every batch, any site, plus org-level undispatched
  stock); a concrete list restricts to batches dispatched to those sites
  specifically (undispatched batches have no `site_id` and so can never
  match a concrete list — correct, since that stock isn't at any site yet).
  An empty list means "no accessible sites" and returns nothing.
  """
  def list_products_with_site_batches_paginated(organization_id, site_ids, page \\ 1, opts \\ [])

  def list_products_with_site_batches_paginated(_organization_id, [], page, _opts) do
    from(p in Product, where: false) |> Repo.paginate(page: page)
  end

  def list_products_with_site_batches_paginated(organization_id, site_ids, page, opts) do
    search = Keyword.get(opts, :search)

    query =
      from(p in Product,
        join: b in ThamaniDawa.Batches.Batch,
        on: b.product_id == p.id,
        where: p.organization_id == ^organization_id,
        distinct: true,
        order_by: [asc: p.id]
      )

    query
    |> filter_by_site_ids(site_ids)
    |> filter_search(search)
    |> Repo.paginate(page: page, page_size: page_size(opts))
  end

  defp filter_by_site_ids(query, nil), do: query

  defp filter_by_site_ids(query, site_ids) when is_list(site_ids),
    do: where(query, [_p, b], b.site_id in ^site_ids)

  def list_products_paginated(organization_id, page \\ 1, opts \\ []) do
    from(p in Product, where: p.organization_id == ^organization_id, order_by: [asc: p.id])
    |> filter_search(Keyword.get(opts, :search))
    |> filter_category(Keyword.get(opts, :category))
    |> filter_flag(:is_otc, Keyword.get(opts, :is_otc))
    |> filter_flag(:is_dangerous_drug, Keyword.get(opts, :is_dangerous_drug))
    |> Repo.paginate(page: page, page_size: page_size(opts))
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

  defp page_size(opts) do
    case Keyword.get(opts, :page_size, 8) do
      size when is_integer(size) and size > 0 and size <= 100 -> size
      _ -> 8
    end
  end

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
          gtin: p.gtin,
          price: p.price,
          stock: sum(b.remaining_quantity)
        }
    )
  end

  @doc """
  Searches a site's active catalog for Quick sale. Returns at most `limit`
  products with approved batches. With an empty search, out-of-stock products
  are omitted; a non-empty search includes them so they can be shown as unavailable.
  """
  def quick_sale_products_for_site(organization_id, site_id, search, category, limit) do
    search = String.trim(search || "")

    query =
      from p in Product,
        join: b in ThamaniDawa.Batches.Batch,
        on: b.product_id == p.id,
        where: p.organization_id == ^organization_id,
        where: p.is_active == true,
        where: p.is_otc == true and p.is_dangerous_drug == false,
        where: b.site_id == ^site_id,
        where: not is_nil(b.received_at) and not is_nil(b.approver_id),
        where: b.expiry_date > ^ThamaniDawa.BusinessDate.today(),
        group_by: p.id,
        order_by: [asc: p.generic_name],
        select: %{
          id: p.id,
          generic_name: p.generic_name,
          brand_name: p.brand_name,
          category: p.category,
          gtin: p.gtin,
          price: p.price,
          stock: sum(b.remaining_quantity)
        }

    query
    |> filter_quick_sale_search(search)
    |> filter_quick_sale_category(category)
    |> maybe_hide_out_of_stock(search)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Fetches a single product in the same shape as `quick_sale_products_for_site/5`
  (id, names, category, gtin, price, aggregated site stock) — used when a
  scanned barcode resolves to a product via a batch-number fallback rather
  than the catalog search.
  """
  def quick_sale_product_for_site(organization_id, site_id, product_id) do
    Repo.one(
      from p in Product,
        join: b in ThamaniDawa.Batches.Batch,
        on: b.product_id == p.id,
        where: p.organization_id == ^organization_id,
        where: p.id == ^product_id,
        where: p.is_active == true,
        where: p.is_otc == true and p.is_dangerous_drug == false,
        where: b.site_id == ^site_id,
        where: not is_nil(b.received_at) and not is_nil(b.approver_id),
        where: b.expiry_date > ^ThamaniDawa.BusinessDate.today(),
        group_by: p.id,
        select: %{
          id: p.id,
          generic_name: p.generic_name,
          brand_name: p.brand_name,
          category: p.category,
          gtin: p.gtin,
          price: p.price,
          stock: sum(b.remaining_quantity)
        }
    )
  end

  @doc "Lists normalized categories for a site's in-stock Quick sale catalog."
  def quick_sale_categories_for_site(organization_id, site_id) do
    from(p in Product,
      join: b in ThamaniDawa.Batches.Batch,
      on: b.product_id == p.id,
      where: p.organization_id == ^organization_id,
      where: p.is_active == true,
      where: p.is_otc == true and p.is_dangerous_drug == false,
      where: b.site_id == ^site_id,
      where: not is_nil(b.received_at) and not is_nil(b.approver_id),
      where: b.expiry_date > ^ThamaniDawa.BusinessDate.today(),
      where: b.remaining_quantity > 0,
      where: not is_nil(p.category) and p.category != "",
      select: p.category,
      distinct: true
    )
    |> Repo.all()
    |> Enum.map(&Product.normalize_category/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&String.downcase/1)
    |> Enum.sort()
  end

  defp filter_quick_sale_search(query, ""), do: query

  defp filter_quick_sale_search(query, search) do
    pattern = "%#{search}%"

    where(
      query,
      [p, _b],
      ilike(p.generic_name, ^pattern) or ilike(p.brand_name, ^pattern) or
        ilike(p.gtin, ^pattern) or ilike(p.category, ^pattern)
    )
  end

  defp filter_quick_sale_category(query, category) when is_binary(category) do
    case String.trim(category) do
      "" ->
        query

      category ->
        normalized = category |> Product.normalize_category() |> String.downcase()
        where(query, [p, _b], fragment("lower(trim(?))", p.category) == ^normalized)
    end
  end

  defp filter_quick_sale_category(query, _category), do: query

  defp maybe_hide_out_of_stock(query, ""),
    do: having(query, [_p, b], sum(b.remaining_quantity) > 0)

  defp maybe_hide_out_of_stock(query, _search), do: query

  @doc "Gets a single product scoped to an organization. Raises if not found."
  def get_product!(organization_id, id) do
    Repo.get_by!(Product, id: id, organization_id: organization_id)
  end

  @doc "Creates a product under the given organization."
  def create_product(organization_id, attrs) when is_integer(organization_id) do
    %Product{}
    |> Product.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.audited_insert()
  end

  @doc "Updates a product."
  def update_product(%Product{} = product, attrs) do
    product
    |> Product.changeset(attrs)
    |> Repo.audited_update()
  end

  @doc "Friendly label for a product's UN/CEFACT unit-of-measure code."
  def unit_label(nil), do: "unit(s)"
  def unit_label("H87"), do: "piece(s)"
  def unit_label("U2"), do: "tablet(s)"
  def unit_label("C62"), do: "unit(s)"
  def unit_label("KGM"), do: "kilogram(s)"
  def unit_label("GRM"), do: "gram(s)"
  def unit_label("MGM"), do: "milligram(s)"
  def unit_label("LTR"), do: "litre(s)"
  def unit_label("MLT"), do: "millilitre(s)"
  def unit_label("AV"), do: "capsule(s)"
  def unit_label("PK"), do: "pack(s)"
  def unit_label("PA"), do: "packet(s)"
  def unit_label(unit), do: if(String.ends_with?(unit, "(s)"), do: unit, else: "#{unit}(s)")

  @doc "A received or on-hand count of trade items. One serialized pack is one unit."
  def format_unit_count(1), do: "1 unit"
  def format_unit_count(quantity) when is_integer(quantity), do: "#{quantity} units"
  def format_unit_count(_quantity), do: "—"

  @doc "What one trade item contains, from the GTIN, for example \"20 tablet(s)\"."
  def format_net_content(%{net_content_quantity: quantity, net_content_uom: uom})
      when is_integer(quantity) and quantity > 0 and is_binary(uom) and uom != "" do
    "#{quantity} #{unit_label(uom)}"
  end

  def format_net_content(_product), do: nil

  @doc "Returns true if the product has pack packaging metadata configured."
  def has_packaging?(nil), do: false

  def has_packaging?(%{pack_uom: pack_uom, units_per_pack: units_per_pack})
      when is_binary(pack_uom) and pack_uom != "" and is_integer(units_per_pack) and
             units_per_pack > 0,
      do: true

  def has_packaging?(_), do: false

  @doc "Formats a pack label considering pluralization."
  def pack_label(pack_uom, 1) when is_binary(pack_uom), do: pack_uom

  def pack_label(pack_uom, _count) when is_binary(pack_uom) do
    if String.ends_with?(pack_uom, ["s", "x", "ch", "sh"]) do
      "#{pack_uom}es"
    else
      "#{pack_uom}s"
    end
  end

  def pack_label(pack_uom, _count), do: to_string(pack_uom)

  @doc """
  Formats a quantity with base unit and packaging conversion if configured.
  E.g. 500 tablets -> "500 tablet(s) (5 cartons)"
  If not divisible evenly: "520 tablet(s) (5 cartons + 20 tablet(s))"
  """
  def format_quantity_with_packaging(quantity, product) do
    base_label = unit_label(product && product.uom)

    if has_packaging?(product) and is_integer(quantity) and quantity > 0 do
      "#{quantity} #{base_label}#{pack_conversion_suffix(quantity, product, base_label)}"
    else
      "#{quantity} #{base_label}"
    end
  end

  defp pack_conversion_suffix(quantity, product, base_label) do
    packs = div(quantity, product.units_per_pack)
    remainder = rem(quantity, product.units_per_pack)
    pack_str = pack_label(product.pack_uom, packs)

    case {packs, remainder} do
      {p, 0} when p > 0 -> " (#{p} #{pack_str})"
      {p, r} when p > 0 and r > 0 -> " (#{p} #{pack_str} + #{r} #{base_label})"
      _ -> ""
    end
  end

  @doc "Returns a packaging summary string for a product, e.g. for badges or stats."
  def format_packaging_summary(quantity, product) do
    if has_packaging?(product) and is_integer(quantity) and quantity > 0 do
      packs = div(quantity, product.units_per_pack)
      remainder = rem(quantity, product.units_per_pack)
      pack_str = pack_label(product.pack_uom, packs)
      base_label = unit_label(product.uom)

      case {packs, remainder} do
        {p, 0} when p > 0 -> "#{p} #{pack_str}"
        {p, r} when p > 0 -> "#{p} #{pack_str} + #{r} #{base_label}"
        _ -> nil
      end
    else
      nil
    end
  end
end
