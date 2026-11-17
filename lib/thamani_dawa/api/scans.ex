defmodule ThamaniDawa.Api.Scans do
  @moduledoc """
  Resolves a scanner payload or a typed GTIN to approved stock.

  The raw string is what the phone sends. A GS1 element string is decoded
  first so batch and expiry survive. A plain GTIN is looked up as typed,
  which is what the pharmacy scan screen does today.
  """

  alias ThamaniDawa.Batches
  alias ThamaniDawa.GS1Decoder
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites

  def lookup(organization_id, site_id, raw) when is_binary(raw) do
    raw = String.trim(raw)

    if raw == "" do
      {:error, :bad_request}
    else
      decoded = decode(raw)
      gtin = (decoded && decoded.gtin) || raw

      result =
        case Batches.find_approved_batches_by_gtin(organization_id, gtin, site_opts(site_id)) do
          {:ok, batches} ->
            found(organization_id, batches)

          {:error, :not_at_site} ->
            %{state: "not_at_site", decoded: decoded, product: nil, batches: []}

          {:error, :not_found} ->
            %{state: "unavailable", decoded: decoded, product: nil, batches: []}
        end

      {:ok, Map.put(result, :decoded, decoded)}
    end
  end

  def lookup(_organization_id, _site_id, _raw), do: {:error, :bad_request}

  defp found(organization_id, batches) do
    product = Products.get_product!(organization_id, hd(batches).product_id)

    site =
      case hd(batches).site_id do
        nil -> nil
        site_id -> Sites.get_site!(organization_id, site_id)
      end

    %{
      state: "found",
      product: product,
      site: site,
      batches: batches,
      total_quantity: Enum.reduce(batches, 0, &(&1.remaining_quantity + &2))
    }
  end

  defp decode(raw) do
    case GS1Decoder.parse(raw) do
      {:ok, decoded} ->
        %{
          gtin: decoded.gtin,
          batch_no: decoded.batch_no,
          production_date: decoded.production_date,
          expiry_date: decoded.expiry_date,
          serial: decoded.serial,
          gln: decoded.gln
        }

      {:error, _reason} ->
        nil
    end
  end

  defp site_opts(nil), do: []
  defp site_opts(site_id), do: [site_id: site_id]
end
