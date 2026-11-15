defmodule ThamaniDawa.Grp do
  @moduledoc """
  Thin HTTP client for the GS1 Global Registry Platform licences API
  (`POST /grp/v3.2/licences/{TYPE}`), the same call shape as
  `ThamaniDawa.VerifyGtin` and gs1_admin's `ActivateApis.get_prefix!/2`.

  Used by the background verification jobs enqueued at onboarding: a GS1
  company prefix is verified under the `GCP` licence type and a Global
  Location Number under `GLN`. A non-empty licence list means the identifier
  is registered; an empty list means the registry simply doesn't know it.

  Endpoint, credentials, retry policy, and the HTTP adapter can all be
  overridden via `config :thamani_dawa, ThamaniDawa.Grp` — which is how the
  test suite swaps in a `Req.Test` stub instead of reaching the live registry.

  Definitive results are cached briefly via `ThamaniDawa.RegistryCache`
  (disabled in tests) to absorb near-duplicate lookups for the same
  identifier in quick succession.
  """

  alias ThamaniDawa.RegistryCache

  @default_base_url "https://grp.gs1.org"
  # Shared GS1 GRP key; override per-environment with `GS1_GRP_API_KEY`.
  @default_api_key "5c969e5eb17a4704a07c9ad7557190fa"

  @type licence :: map()

  @doc """
  Verifies a GS1 company prefix (Global Company Prefix) against the registry.

  Returns `{:ok, :verified, licence}` when the registry answers with at least
  one licence record whose `licenceStatus` is `"ACTIVE"`, `{:ok, :inactive,
  licence}` when the record exists but its status is anything else (including
  status strings we haven't catalogued yet — only `"ACTIVE"` is confirmed, so
  unrecognized values are treated conservatively as not currently valid), and
  `{:ok, :not_verified}` when the registry has no record at all — an
  unregistered prefix is *not* an error here. Failures are kept distinct so a
  broken deployment is distinguishable from a broken registry:
  `{:error, :unauthorized}` for `401`/`403` (our API key is rejected — a
  configuration fault on our side), `{:error, :provider_error}` for any other
  non-2xx, and `{:error, :timeout}` for any transport failure.
  """
  @spec verify_prefix(String.t()) ::
          {:ok, :verified, licence()}
          | {:ok, :inactive, licence()}
          | {:ok, :not_verified}
          | verify_error()
  def verify_prefix(prefix) do
    RegistryCache.fetch({:grp, "GCP", prefix}, fn -> verify("GCP", prefix) end)
  end

  @doc """
  Verifies a GLN against the registry. Same contract as `verify_prefix/1`.
  """
  @spec verify_gln(String.t()) ::
          {:ok, :verified, licence()}
          | {:ok, :inactive, licence()}
          | {:ok, :not_verified}
          | verify_error()
  def verify_gln(gln) do
    RegistryCache.fetch({:grp, "GLN", gln}, fn -> verify("GLN", gln) end)
  end

  @type verify_error :: {:error, :unauthorized | :provider_error | :timeout}

  defp verify(type, number) do
    case Req.post(url(type), req_options(number)) do
      {:ok, %Req.Response{status: status, body: [licence | _]}}
      when status in 200..299 and is_map(licence) ->
        if active?(licence) do
          {:ok, :verified, licence}
        else
          {:ok, :inactive, licence}
        end

      {:ok, %Req.Response{status: status, body: _body}} when status in 200..299 ->
        {:ok, :not_verified}

      {:ok, %Req.Response{status: status}} when status in [401, 403] ->
        {:error, :unauthorized}

      {:ok, %Req.Response{}} ->
        {:error, :provider_error}

      {:error, _reason} ->
        {:error, :timeout}
    end
  end

  # Only "ACTIVE" is a confirmed status value from the live registry; every
  # other string (including ones we haven't seen yet) is treated as inactive
  # rather than assumed valid, until the full vocabulary is confirmed with
  # the GS1 team.
  defp active?(licence) do
    case Map.get(licence, "licenceStatus") do
      status when is_binary(status) -> String.upcase(String.trim(status)) == "ACTIVE"
      _ -> false
    end
  end

  defp url(type),
    do: Keyword.get(config(), :base_url, @default_base_url) <> "/grp/v3.2/licences/#{type}"

  defp req_options(number) do
    options = [
      headers: [
        {"Content-Type", "application/json"},
        {"Cache-Control", "no-cache"},
        {"APIKEY", Keyword.get(config(), :api_key) || @default_api_key}
      ],
      json: [number],
      retry: Keyword.get(config(), :retry, :transient),
      max_retries: 5,
      receive_timeout: 60_000
    ]

    case Keyword.get(config(), :plug) do
      nil -> options
      plug -> Keyword.put(options, :plug, plug)
    end
  end

  defp config, do: Application.get_env(:thamani_dawa, __MODULE__, [])
end
