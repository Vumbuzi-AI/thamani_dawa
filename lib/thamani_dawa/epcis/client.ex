defmodule ThamaniDawa.Epcis.Client do
  @moduledoc """
  HTTP client for the PPB Track & Trace Hub capture endpoint. One event per
  capture document (ordering is enforced by submission order), `X-API-Key`
  auth, JSON-LD body. The Hub issues separate credentials per partner tier
  (facility vs distributor), so each submission picks the capture path
  matching the event's `participant_tier`. The API key is normally the
  platform-wide one configured here, but an organization may supply its own
  (`Organizations.set_epcis_api_key/3`) — when present, the caller passes it
  as `api_key_override` and it wins over the platform key for that one
  submission. Responses are classified for the submission worker:

    * `{:accepted, status, body}` — stored by the Hub (2xx)
    * `{:duplicate, status, body}` — 409; the event already made it
    * `{:rejected, status, body}` — 400-level; never auto-retried
    * `{:retry, reason}` — transient (429/5xx/transport); retried with backoff

  The real HTTP call sits behind the `submit_document/3` callback so tests
  swap it via the `:client` application env.
  """

  alias ThamaniDawa.Epcis.Document

  @callback submit_document(map(), String.t(), String.t() | nil) ::
              {:ok, integer(), map()} | {:error, term()}

  def enabled?, do: Keyword.get(config(), :enabled, false) && config()[:base_url] not in [nil, ""]

  def submit(payload, tier, api_key_override \\ nil)
      when is_map(payload) and is_binary(tier) do
    document = Document.wrap(payload)

    case impl().submit_document(document, tier, api_key_override) do
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
  def submit_document(document, tier, api_key_override) do
    creds = credentials(tier)
    api_key = api_key_override || creds.api_key

    request =
      Req.new(
        base_url: Keyword.fetch!(config(), :base_url),
        url: creds.capture_path,
        headers: [
          {"x-api-key", api_key},
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

  @doc """
  Capture path and platform-wide API key for a partner tier. The Hub issues
  distinct credentials per tier; `"distributor"` falls back to the facility
  credential/path when a distributor-specific one isn't configured, so
  single-tier deployments keep working unchanged. An organization's own key
  (see `submit/3`) is applied on top of this, not inside it.
  """
  def credentials("distributor") do
    cfg = config()

    %{
      capture_path:
        Keyword.get(cfg, :distributor_capture_path) || Keyword.fetch!(cfg, :capture_path),
      api_key: Keyword.get(cfg, :distributor_api_key) || Keyword.fetch!(cfg, :api_key)
    }
  end

  def credentials(_tier) do
    cfg = config()
    %{capture_path: Keyword.fetch!(cfg, :capture_path), api_key: Keyword.fetch!(cfg, :api_key)}
  end

  defp impl do
    Keyword.get(config(), :client, __MODULE__)
  end

  defp config do
    Application.get_env(:thamani_dawa, __MODULE__, [])
  end
end
