defmodule ThamaniDawa.Products.Importer do
  @moduledoc """
  CSV product-catalogue import. Deliberately product-only for now — it
  creates/updates `Product` rows via the same `Product.changeset/2` the
  manual-entry form uses (so an import can never pass something the form
  would reject), and never touches batches/stock. Column names in the
  uploaded file are user-controlled, so the caller maps them to our field
  keys via `auto_map_columns/1` (best-effort) before building rows.
  """

  alias ThamaniDawa.Products
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.Repo

  NimbleCSV.define(__MODULE__.Parser, separator: ",", escape: "\"")

  @fields [
    %{key: :generic_name, label: "Generic name", required: false},
    %{key: :brand_name, label: "Brand name", required: false},
    %{key: :gtin, label: "GTIN", required: true},
    %{key: :price, label: "Price", required: true},
    %{key: :uom, label: "Unit of measure", required: true},
    %{key: :category, label: "Category", required: false},
    %{key: :manufacturer, label: "Manufacturer", required: false},
    %{key: :reorder_level, label: "Reorder level", required: false},
    %{key: :is_otc, label: "Over-the-counter (yes/no)", required: false},
    %{key: :is_dangerous_drug, label: "Dangerous drug (yes/no)", required: false}
  ]

  @doc "The importable fields, in template-column order."
  def fields, do: @fields

  @doc "Header row for the downloadable CSV template."
  def template_headers, do: Enum.map(@fields, & &1.label)

  @doc """
  Parses a CSV binary into `{:ok, {headers, rows}}`, where `rows` is a list
  of raw string lists (not yet mapped to our field keys). Blank trailing
  rows are dropped. Returns `{:error, :empty_file}` for a header-only or
  empty upload, `{:error, :malformed_csv}` if the file can't be parsed.
  """
  def parse(binary) when is_binary(binary) do
    case __MODULE__.Parser.parse_string(binary, skip_headers: false) do
      [] ->
        {:error, :empty_file}

      [headers | rows] ->
        rows = Enum.reject(rows, &Enum.all?(&1, fn cell -> String.trim(cell) == "" end))

        if rows == [] do
          {:error, :empty_file}
        else
          {:ok, {headers, rows}}
        end
    end
  rescue
    _ -> {:error, :malformed_csv}
  end

  @doc """
  Best-effort mapping from the uploaded file's header row to our field
  keys, matched case/whitespace-insensitively against each field's label
  and key. Ambiguous or unmatched fields are left unmapped (`nil`) for the
  user to fill in by hand on the mapping step.
  """
  def auto_map_columns(headers) do
    normalized = Enum.map(headers, &{&1, normalize(&1)})

    Map.new(@fields, fn field ->
      match =
        Enum.find(normalized, fn {_header, norm} ->
          norm == normalize(field.label) or norm == normalize(to_string(field.key))
        end)

      {field.key, match && elem(match, 0)}
    end)
  end

  defp normalize(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "")
  end

  @doc """
  Builds preview rows for a mapping (`%{field_key => header_or_nil}`)
  against the parsed `headers`/`rows`, without writing anything to the
  database. Each row is `%{index:, attrs:, changeset:, status:}`, where
  `status` is `:valid`, `:invalid`, `:duplicate_in_file`, or
  `:exists_in_catalogue`.
  """
  def build_preview_rows(organization_id, headers, rows, mapping) do
    column_index = Map.new(Enum.with_index(headers), fn {header, i} -> {header, i} end)

    existing_gtins =
      organization_id
      |> Products.list_products()
      |> MapSet.new(& &1.gtin)

    rows
    |> Enum.with_index(1)
    |> Enum.map(fn {row, index} ->
      attrs = row_attrs(row, column_index, mapping)
      changeset = Product.changeset(%Product{}, attrs)
      {index, attrs, changeset}
    end)
    |> mark_statuses(existing_gtins)
  end

  defp row_attrs(row, column_index, mapping) do
    attrs =
      @fields
      |> Enum.map(fn field ->
        value =
          case Map.get(mapping, field.key) do
            nil -> nil
            header -> row |> Enum.at(Map.fetch!(column_index, header)) |> then(&String.trim/1)
          end

        {Atom.to_string(field.key), cast_value(field.key, value)}
      end)
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    Map.put(attrs, "inventory_type", "medicine")
  end

  defp cast_value(_key, nil), do: nil
  defp cast_value(_key, ""), do: nil
  defp cast_value(key, value) when key in [:is_otc, :is_dangerous_drug], do: truthy?(value)
  defp cast_value(_key, value), do: value

  defp truthy?(value), do: String.downcase(value) in ["yes", "y", "true", "1"]

  defp mark_statuses(rows, existing_gtins) do
    {result, _seen} =
      Enum.map_reduce(rows, MapSet.new(), fn {index, attrs, changeset}, seen ->
        gtin = normalized_gtin(changeset)

        status =
          cond do
            not changeset.valid? -> :invalid
            gtin && MapSet.member?(seen, gtin) -> :duplicate_in_file
            gtin && MapSet.member?(existing_gtins, gtin) -> :exists_in_catalogue
            true -> :valid
          end

        seen = if gtin, do: MapSet.put(seen, gtin), else: seen
        {%{index: index, attrs: attrs, changeset: changeset, status: status}, seen}
      end)

    result
  end

  defp normalized_gtin(changeset), do: Ecto.Changeset.get_field(changeset, :gtin)

  @doc """
  Creates a `Product` for every `:valid`-status preview row, in a single
  transaction. Rows with any other status are skipped — the caller already
  showed them as excluded in the preview. Returns `{:ok, created_count}` or
  `{:error, index, changeset}` for the first row that fails to insert
  despite having previewed as valid (e.g. a GTIN another request just
  took).
  """
  def import_rows(organization_id, preview_rows) do
    valid_rows = Enum.filter(preview_rows, &(&1.status == :valid))

    Repo.transaction(fn ->
      case insert_rows(organization_id, valid_rows) do
        {:error, index, changeset} -> Repo.rollback({index, changeset})
        count -> count
      end
    end)
  end

  defp insert_rows(organization_id, rows) do
    Enum.reduce_while(rows, 0, fn row, count ->
      case Products.create_product(organization_id, row.attrs) do
        {:ok, _product} -> {:cont, count + 1}
        {:error, changeset} -> {:halt, {:error, row.index, changeset}}
      end
    end)
  end
end
