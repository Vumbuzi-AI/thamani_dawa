defmodule ThamaniDawa.Gs1Api.Client do
  @moduledoc """
  Thin HTTP client for the `gs1_admin` GS1 API (serialisation.md §4).

  GS1 is the authority for identifier issuance: every SSCC and every serialised
  GTIN in this app comes back from one of these calls, never from local
  arithmetic. This module only speaks HTTP — auditing, idempotency keys and
  persistence live in `ThamaniDawa.Gs1Api`.

  Endpoint, token, timeout, retry policy and the HTTP adapter are all
  configurable via `config :thamani_dawa, ThamaniDawa.Gs1Api`, which is how the
  test suite swaps in a `Req.Test` stub instead of reaching a live deployment.
  """

  require Logger

  alias ThamaniDawa.Gs1Api.Error

  # Generation is not naturally idempotent — a retried create mints a *new*
  # code (§4.5) — so writes never auto-retry and are given a long budget
  # (serialised runs of 100k+ serials are slow). Reads may retry freely.
  @write_timeout :timer.minutes(5)
  @read_timeout :timer.seconds(30)

  @doc """
  POSTs `payload` to `path` on the GS1 host.

  `:idempotent?` (default `false`) marks a call as safe to retry: reads pass
  `true`, generation calls must not.
  """
  @spec post(String.t(), map(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def post(path, payload, opts \\ []) do
    with {:ok, base_url} <- fetch_base_url(),
         {:ok, token} <- fetch_token() do
      request(base_url <> path, payload, token, opts)
    end
  end

  defp request(url, payload, token, opts) do
    case Req.post(url, req_options(payload, token, opts)) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        error = Error.from_response(status, body)
        Logger.warning("GS1 API #{url} failed: #{status} #{error.message}")
        {:error, error}

      {:error, reason} ->
        Logger.warning("GS1 API #{url} unreachable: #{inspect(reason)}")
        {:error, Error.transport(reason)}
    end
  end

  defp req_options(payload, token, opts) do
    idempotent? = Keyword.get(opts, :idempotent?, false)

    options = [
      headers: [
        {"Content-Type", "application/json"},
        {"Authorization", "Bearer #{token}"}
      ],
      json: payload,
      retry: retry_policy(idempotent?),
      max_retries: 3,
      receive_timeout:
        Keyword.get(opts, :receive_timeout) ||
          Keyword.get(config(), :receive_timeout) ||
          if(idempotent?, do: @read_timeout, else: @write_timeout)
    ]

    case Keyword.get(config(), :plug) do
      nil -> options
      plug -> Keyword.put(options, :plug, plug)
    end
  end

  defp retry_policy(false), do: false
  defp retry_policy(true), do: Keyword.get(config(), :retry, :transient)

  defp fetch_base_url do
    case Keyword.get(config(), :base_url) do
      url when is_binary(url) and url != "" -> {:ok, String.trim_trailing(url, "/")}
      _ -> {:error, Error.not_configured()}
    end
  end

  defp fetch_token do
    case Keyword.get(config(), :api_token) do
      token when is_binary(token) and token != "" -> {:ok, token}
      _ -> {:error, Error.not_configured()}
    end
  end

  defp config, do: Application.get_env(:thamani_dawa, ThamaniDawa.Gs1Api, [])
end
