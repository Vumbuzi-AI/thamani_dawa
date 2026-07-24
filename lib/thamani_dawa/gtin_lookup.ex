defmodule ThamaniDawa.GtinLookup do
  @moduledoc """
  Looks up a product's catalog data by GTIN against the external GS1 GRP registry — the same
  external source GHCE/medic's own equivalent integrates with (`POST /grp/v3.2/gtins/verified`).

  Stateless and tenant-agnostic on purpose: this is read-only, external, non-tenant data, and
  never writes anything itself. Callers (e.g. `ThamaniDawaWeb.ProductLive.Index`) decide whether
  and how to use a result inside their own org-scoped context — persistence still only ever
  happens through `ThamaniDawa.Products.create_product/2`, which enforces org-scoping as usual.
  """

  require Logger

  alias ThamaniDawa.Gtin

  @path "/grp/v3.2/gtins/verified"

  @type prefill :: %{
          optional(:brand_name) => String.t(),
          optional(:generic_name) => String.t(),
          optional(:manufacturer) => String.t(),
          optional(:uom) => String.t(),
          gtin: String.t()
        }

  @doc """
  Looks up `raw_gtin`. Validates/normalizes locally first via `ThamaniDawa.Gtin.normalize/1` —
  malformed input never reaches the network. Only fields the provider actually returned are
  present in the success map (besides `:gtin`, always included, normalized).
  """
  @spec lookup(String.t()) ::
          {:ok, prefill}
          | {:error, :invalid_gtin | :not_found | :timeout | :provider_error}
  def lookup(raw_gtin) do
    with {:ok, normalized} <- Gtin.normalize(raw_gtin) do
      request(normalized)
    end
  end

  defp request(normalized_gtin) do
    config = Application.get_env(:thamani_dawa, __MODULE__, [])
    api_key = Keyword.get(config, :api_key)

    req_opts =
      [receive_timeout: 10_000, retry: false, headers: [{"APIKEY", api_key}]]
      |> Keyword.merge(Keyword.delete(config, :api_key))

    req = Req.new(req_opts)

    case Req.post(req, url: @path, json: [normalized_gtin]) do
      {:ok, %Req.Response{status: 200, body: [%{"validationErrors" => errors} | _]}}
      when errors != [] ->
        Logger.debug("GTIN #{normalized_gtin} not verified by GS1: #{inspect(errors)}")
        {:error, :not_found}

      {:ok, %Req.Response{status: 200, body: [first | _]}} when is_map(first) ->
        Logger.debug("GTIN lookup match for #{normalized_gtin}: #{inspect(first)}")
        {:ok, extract(first, normalized_gtin)}

      {:ok, %Req.Response{status: 200, body: []}} ->
        {:error, :not_found}

      {:ok, %Req.Response{}} ->
        {:error, :provider_error}

      {:error, %{reason: :timeout}} ->
        {:error, :timeout}

      {:error, _exception} ->
        {:error, :timeout}
    end
  end

  defp extract(drug, gtin) do
    %{gtin: gtin}
    |> put_if_present(:brand_name, first_value(drug["brandName"]))
    |> put_if_present(:generic_name, first_value(drug["productDescription"]))
    |> put_if_present(:manufacturer, licensee_name(drug["gs1Licence"]))
    |> put_if_present(:uom, first_unit_code(drug["netContent"]))
  end

  defp first_value([%{"value" => value} | _]) when is_binary(value) and value != "", do: value
  defp first_value(_), do: nil

  defp first_unit_code([%{"unitCode" => code} | _]) when is_binary(code) and code != "",
    do: code

  defp first_unit_code(_), do: nil

  defp licensee_name(%{"licenseeName" => name}) when is_binary(name) and name != "", do: name
  defp licensee_name(_), do: nil

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)
end
