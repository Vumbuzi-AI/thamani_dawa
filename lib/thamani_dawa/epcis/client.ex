defmodule ThamaniDawa.Epcis.Client do
  @moduledoc """
  HTTP client for the PPB Track & Trace Hub capture endpoint. One event per
  capture document (ordering is enforced by submission order), `X-API-Key`
  auth, JSON-LD body. Responses are classified for the submission worker:

    * `{:accepted, status, body}` — stored by the Hub (2xx)
    * `{:duplicate, status, body}` — 409; the event already made it
    * `{:rejected, status, body}` — 400-level; never auto-retried
    * `{:retry, reason}` — transient (429/5xx/transport); retried with backoff

  The real HTTP call sits behind the `submit_document/1` callback so tests
  swap it via the `:client` application env.
  """

  alias ThamaniDawa.Epcis.Document

  @callback submit_document(map()) :: {:ok, integer(), map()} | {:error, term()}

  def enabled?, do: Keyword.get(config(), :enabled, false) && config()[:base_url] not in [nil, ""]

  def submit(payload) when is_map(payload) do
    document = Document.wrap(payload)

    case impl().submit_document(document) do
      {:ok, status, body} when status in 200..299 -> {:accepted, status, body}
      {:ok, 409, body} -> {:duplicate, 409, body}
      {:ok, status, body} when status in [408, 429] -> {:retry, {:http, status, body}}
      {:ok, status, body} when status in 400..499 -> {:rejected, status, body}
      {:ok, status, body} -> {:retry, {:http, status, body}}
      {:error, reason} -> {:retry, reason}
    end
  end

  @behaviour __MODULE__

  @impl true
  def submit_document(document) do
    request =
      Req.new(
        base_url: Keyword.fetch!(config(), :base_url),
        url: Keyword.fetch!(config(), :capture_path),
        headers: [
          {"x-api-key", Keyword.fetch!(config(), :api_key)},
          {"content-type", "application/ld+json"}
        ],
        body: Jason.encode!(document),
        receive_timeout: 30_000,
        retry: false
      )

    case Req.post(request) do
      {:ok, %Req.Response{status: status, body: body}} -> {:ok, status, normalize_body(body)}
      {:error, exception} -> {:error, exception}
    end
  end

  defp normalize_body(body) when is_map(body), do: body
  defp normalize_body(body) when is_binary(body), do: %{"raw" => body}
  defp normalize_body(body), do: %{"raw" => inspect(body)}

  defp impl do
    Keyword.get(config(), :client, __MODULE__)
  end

  defp config do
    Application.get_env(:thamani_dawa, __MODULE__, [])
  end
end
