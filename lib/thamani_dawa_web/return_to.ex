defmodule ThamaniDawaWeb.ReturnTo do
  @moduledoc false

  def safe(path, default) when is_binary(path) and is_binary(default) do
    if String.starts_with?(path, "/") and not String.starts_with?(path, "//") and
         not String.contains?(path, "://") do
      path
    else
      default
    end
  end

  def safe(_path, default), do: default

  def with_query(path, return_to) when is_binary(path) and is_binary(return_to) do
    sep = if String.contains?(path, "?"), do: "&", else: "?"
    path <> sep <> "return_to=" <> URI.encode_www_form(return_to)
  end

  @doc "The safe back path from params: `return_to` when it is an in-app path, else `fallback`."
  def path(%{"return_to" => value}, fallback), do: safe(value, fallback)
  def path(_params, fallback), do: fallback

  @doc "A back label for a known list path, e.g. \"Back to Orders\"."
  def label(path, default) do
    case path |> URI.parse() |> Map.get(:path) do
      "/distributor/orders" -> "Back to Orders"
      "/distributor/shipments" -> "Back to Shipments"
      "/distributor/receiving" -> "Back to Receiving"
      "/distributor/returns" -> "Back to Supplier returns"
      "/distributor/customer-returns" -> "Back to Customer returns"
      "/distributor/customers" -> "Back to Customers"
      "/distributor/expiry-write-offs" -> "Back to Expiry write-offs"
      "/distributor" -> "Back to Dashboard"
      "/manufacturer/products" -> "Back to Products"
      "/manufacturer/inventory" -> "Back to Inventory"
      "/manufacturer/aggregations" -> "Back to Aggregations"
      "/manufacturer/shipments" -> "Back to Shipments"
      "/manufacturer" -> "Back to Dashboard"
      "/manufacturer/products/" <> rest -> manufacturer_product_label(rest, default)
      _ -> default
    end
  end

  defp manufacturer_product_label(rest, default) do
    case String.split(rest, "/") do
      [_gtin, "serials"] -> "Back to Batches"
      [_gtin, "ssccs"] -> "Back to Shipper SSCCs"
      [_id] -> "Back to Product"
      _ -> default
    end
  end
end
