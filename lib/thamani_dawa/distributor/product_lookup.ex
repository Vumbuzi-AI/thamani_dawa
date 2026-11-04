defmodule ThamaniDawa.Distributor.ProductLookup do
  @moduledoc """
  Resolves product details for a scanned GTIN, in order:

    1. an earlier scan of the same GTIN in this organization whose product
       was already resolved (`"previous_scan"`)
    2. the organization's own product catalogue (`"catalogue"`)
    3. Verified by GS1, via `ThamaniDawa.GtinLookup` (`"verified_by_gs1"`)

  A GTIN found nowhere is `{:error, :gtin_not_found}`. When the GS1 registry
  is simply unreachable, the scan is still allowed — it is recorded as
  `"unverified"` with no product detail, rather than blocked.

  Called outside any database transaction so a slow registry call never
  holds a row lock.
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.Distributor.ShipmentItem
  alias ThamaniDawa.GtinLookup
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.Repo

  @type result :: %{
          product_id: integer() | nil,
          product_name: String.t() | nil,
          source: String.t()
        }

  @spec lookup(pos_integer(), String.t()) :: {:ok, result()} | {:error, :gtin_not_found}
  def lookup(organization_id, gtin) do
    previous_scan(organization_id, gtin) || catalogue(organization_id, gtin) ||
      verified_by_gs1(gtin)
  end

  defp previous_scan(organization_id, gtin) do
    query =
      from i in ShipmentItem,
        where: i.organization_id == ^organization_id and i.gtin == ^gtin,
        where: i.product_source != "unverified",
        order_by: [desc: i.id],
        limit: 1,
        select: %{product_id: i.product_id, product_name: i.product_name}

    case Repo.one(query) do
      nil -> nil
      found -> {:ok, Map.put(found, :source, "previous_scan")}
    end
  end

  defp catalogue(organization_id, gtin) do
    case Repo.get_by(Product, organization_id: organization_id, gtin: gtin) do
      nil ->
        nil

      product ->
        {:ok,
         %{
           product_id: product.id,
           product_name: product.generic_name || product.brand_name,
           source: "catalogue"
         }}
    end
  end

  defp verified_by_gs1(gtin) do
    case GtinLookup.lookup(gtin) do
      {:ok, prefill} ->
        {:ok,
         %{
           product_id: nil,
           product_name: prefill[:brand_name] || prefill[:generic_name],
           source: "verified_by_gs1"
         }}

      {:error, reason} when reason in [:not_found, :invalid_gtin] ->
        {:error, :gtin_not_found}

      {:error, _unreachable} ->
        {:ok, %{product_id: nil, product_name: nil, source: "unverified"}}
    end
  end
end
