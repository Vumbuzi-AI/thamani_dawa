defmodule ThamaniDawa.VerifyGtin do
  @moduledoc """
  Thin HTTP client for the GS1 GRP verified-GTIN endpoint
  (`POST /grp/v3.2/gtins/verified`).

  Endpoint, credentials, retry policy, and the HTTP adapter can all be
  overridden via `config :thamani_dawa, ThamaniDawa.GtinLookup` — which is how
  the test suite swaps in a `Req.Test` stub instead of reaching the live
  registry. Absent config, the defaults below are used.
  """

  @path "/grp/v3.2/gtins/verified"
  @default_base_url "https://grp.gs1.org"
  # Shared GS1 GRP key; override per-environment with `GS1_GRP_API_KEY`.
  @default_api_key "5c969e5eb17a4704a07c9ad7557190fa"

  @doc """
  Verifies `gtin` against the registry.

  Returns `{:ok, body}` for a 2xx carrying results and `{:ok, :not_verified}` for a
  2xx carrying none. An unknown GTIN is *not* an error here — the registry answers
  `200` with `validationErrors`, which `ThamaniDawa.GtinLookup` maps to `:not_found`.

  Failures are kept distinct so a broken deployment is distinguishable from a
  broken registry: `{:error, :unauthorized}` for `401`/`403` (our API key is
  rejected — a configuration fault on our side), `{:error, :provider_error}` for
  any other non-2xx, and `{:error, :timeout}` for any transport failure.
  """
  @spec verify(String.t()) ::
          {:ok, list() | :not_verified}
          | {:error, :unauthorized | :provider_error | :timeout}
  def verify(gtin) do
    case Req.post(url(), req_options(gtin)) do
      {:ok, %Req.Response{status: status, body: []}} when status in 200..299 ->
        {:ok, :not_verified}

      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} when status in [401, 403] ->
        {:error, :unauthorized}

      {:ok, %Req.Response{}} ->
        {:error, :provider_error}

      {:error, _reason} ->
        {:error, :timeout}
    end
  end

  defp url, do: Keyword.get(config(), :base_url, @default_base_url) <> @path

  defp req_options(gtin) do
    options = [
      headers: [
        {"Content-Type", "application/json"},
        {"Cache-Control", "no-cache"},
        {"APIKEY", Keyword.get(config(), :api_key) || @default_api_key}
      ],
      json: [gtin],
      retry: Keyword.get(config(), :retry, :transient),
      max_retries: 5,
      receive_timeout: 60_000
    ]

    case Keyword.get(config(), :plug) do
      nil -> options
      plug -> Keyword.put(options, :plug, plug)
    end
  end

  defp config, do: Application.get_env(:thamani_dawa, ThamaniDawa.GtinLookup, [])
end
