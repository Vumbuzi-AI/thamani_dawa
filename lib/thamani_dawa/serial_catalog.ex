defmodule ThamaniDawa.SerialCatalog do
  @moduledoc """
  The serialisation working catalog: the GTINs an organization generates codes
  for (serialisation.md §2.2, `ErpLive.SerialBarcodes`).

  Deliberately separate from `ThamaniDawa.Products`. A distributor serialises
  products it doesn't own, so the catalog can hold GTINs that will never be a
  product row — and a product can exist without ever being serialised.

  **Searching never writes** (§2.4.9). `preview_item/2` returns an *unsaved*
  struct built from GS1's answer; a row only appears once someone saves it
  through `ensure_item/2`. That is what keeps a stray search from littering the
  catalog with GTINs nobody chose.
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Gs1Api
  alias ThamaniDawa.Gtin
  alias ThamaniDawa.Repo
  alias ThamaniDawa.SerialCatalog.CatalogItem

  @doc "Lists an organization's catalog items."
  def list_items(organization_id) do
    Repo.all(
      from i in CatalogItem,
        where: i.organization_id == ^organization_id,
        order_by: [asc: i.gtin]
    )
  end

  @doc """
  Lists an organization's catalog items, paginated.

  Options: `:search` (matches GTIN, name or company) and `:source`.
  """
  def list_items_paginated(organization_id, page \\ 1, opts \\ []) do
    CatalogItem
    |> where([i], i.organization_id == ^organization_id)
    |> filter_by_search(Keyword.get(opts, :search))
    |> filter_by_source(Keyword.get(opts, :source))
    |> order_by([i], asc: i.gtin)
    |> Repo.paginate(page: page)
  end

  defp filter_by_search(query, nil), do: query

  defp filter_by_search(query, search) do
    case String.trim(search) do
      "" ->
        query

      trimmed ->
        pattern = "%#{trimmed}%"

        where(
          query,
          [i],
          ilike(i.gtin, ^pattern) or ilike(i.name, ^pattern) or ilike(i.comp_name, ^pattern)
        )
    end
  end

  defp filter_by_source(query, nil), do: query
  defp filter_by_source(query, ""), do: query
  defp filter_by_source(query, source), do: where(query, [i], i.source == ^source)

  @doc "Gets one catalog item scoped to an organization. Raises if not found."
  def get_item!(organization_id, id) do
    Repo.get_by!(CatalogItem, id: id, organization_id: organization_id)
  end

  @doc "Finds a catalog item by GTIN, or `nil`. The GTIN is normalized first."
  def get_item_by_gtin(organization_id, gtin) do
    case Gtin.normalize(gtin) do
      {:ok, normalized} ->
        Repo.get_by(CatalogItem, organization_id: organization_id, gtin: normalized)

      {:error, _reason} ->
        nil
    end
  end

  @doc """
  Looks a GTIN up for preview — the local catalog first, then GS1.

  Returns `{:ok, item, :catalog | :gs1}` with an item that is *not* persisted
  when it came from GS1. Errors are passed through from `ThamaniDawa.Gs1Api`
  (with their member-facing message intact) plus `:invalid_gtin` for input that
  never reaches the network.
  """
  @spec preview_item(Scope.t(), String.t()) ::
          {:ok, CatalogItem.t(), :catalog | :gs1} | {:error, term()}
  def preview_item(%Scope{} = scope, raw_gtin) do
    with {:ok, gtin} <- Gtin.normalize(raw_gtin) do
      case get_item_by_gtin(scope.organization_id, gtin) do
        %CatalogItem{} = item ->
          {:ok, item, :catalog}

        nil ->
          with {:ok, body} <- Gs1Api.verify_gtin(scope, gtin) do
            {:ok, build_item(scope.organization_id, gtin, body), :gs1}
          end
      end
    end
  end

  @doc """
  Persists a previewed item, or returns the existing row for that GTIN.

  Called at save time, never at search time. Concurrent saves of the same GTIN
  race on the `(organization_id, gtin)` unique index rather than in application
  code, so the loser reads the winner's row instead of erroring.
  """
  @spec ensure_item(integer(), map() | CatalogItem.t()) ::
          {:ok, CatalogItem.t()} | {:error, Ecto.Changeset.t()}
  def ensure_item(organization_id, %CatalogItem{} = item) do
    ensure_item(organization_id, Map.take(item, catalog_fields()))
  end

  def ensure_item(organization_id, attrs) when is_map(attrs) do
    %CatalogItem{organization_id: organization_id}
    |> CatalogItem.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, item} ->
        {:ok, item}

      {:error, changeset} ->
        case existing_for(organization_id, changeset) do
          %CatalogItem{} = existing -> {:ok, existing}
          nil -> {:error, changeset}
        end
    end
  end

  defp existing_for(organization_id, changeset) do
    case Ecto.Changeset.get_field(changeset, :gtin) do
      nil -> nil
      gtin -> Repo.get_by(CatalogItem, organization_id: organization_id, gtin: gtin)
    end
  end

  @doc "Updates a catalog item."
  def update_item(%CatalogItem{} = item, attrs) do
    item
    |> CatalogItem.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a catalog item. Issued codes reference GTINs, not rows, so they survive."
  def delete_item(%CatalogItem{} = item), do: Repo.delete(item)

  @doc "A blank changeset, for the add-to-catalog form."
  def change_item(%CatalogItem{} = item, attrs \\ %{}), do: CatalogItem.changeset(item, attrs)

  defp catalog_fields do
    [
      :gtin,
      :name,
      :description,
      :weight,
      :uom,
      :classification,
      :target_market,
      :comp_name,
      :image,
      :source
    ]
  end

  # GS1's `getbarcode_v2` wraps its payload differently depending on how the
  # product was registered, so unwrap the common envelopes and accept either
  # naming for each field rather than failing on a shape we didn't predict.
  defp build_item(organization_id, gtin, body) do
    attrs = unwrap(body)

    %CatalogItem{
      organization_id: organization_id,
      gtin: gtin,
      name: pick(attrs, ["name", "product_name", "product_description", "description"]),
      description: pick(attrs, ["description", "product_description"]),
      weight: attrs |> pick_any(["weight", "net_content", "netContent"]) |> to_string_or_nil(),
      uom: pick(attrs, ["uom", "unit_of_measure", "unitCode"]),
      classification: pick(attrs, ["classification", "gpc", "gpc_code"]),
      target_market: pick(attrs, ["target_market", "targetMarket"]),
      comp_name: pick(attrs, ["comp_name", "company_name", "member_name", "brand_owner"]),
      image: pick(attrs, ["image", "image_url", "product_image"]),
      source: :external
    }
  end

  defp unwrap(%{"barcode" => %{} = inner}), do: inner
  defp unwrap(%{"data" => %{} = inner}), do: inner
  defp unwrap(%{"product" => %{} = inner}), do: inner
  defp unwrap(%{} = body), do: body
  defp unwrap(_body), do: %{}

  defp pick(attrs, keys) do
    Enum.find_value(keys, fn key ->
      case Map.get(attrs, key) do
        value when is_binary(value) and value != "" -> value
        _ -> nil
      end
    end)
  end

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(value) when is_binary(value), do: value
  defp to_string_or_nil(value), do: to_string(value)

  # Net content often arrives as a number rather than a string.
  defp pick_any(attrs, keys) do
    Enum.find_value(keys, fn key ->
      case Map.get(attrs, key) do
        value when is_binary(value) and value != "" -> value
        value when is_number(value) -> value
        _ -> nil
      end
    end)
  end
end
