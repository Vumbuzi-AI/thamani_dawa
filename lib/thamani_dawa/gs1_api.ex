defmodule ThamaniDawa.Gs1Api do
  @moduledoc """
  The gateway to the `gs1_admin` GS1 API (serialisation.md §4).

  Two responsibilities beyond `ThamaniDawa.Gs1Api.Client`'s raw HTTP:

    * **Idempotency and audit.** Every *generation* call gets a client-generated
      `request_id` persisted to `gs1_requests` as `pending` before the request
      leaves, then settled to `succeeded`/`failed` (§4.5). Nothing here ever
      auto-retries a generation call — a retry mints a new code, so a stranded
      `pending` row is deliberately left for an operator to reconcile.
    * **Response summarising.** A serialised run can return hundreds of
      thousands of serials; only a digest of the response is stored on the
      audit row, never the full payload.

  Read-only calls (`get_sscc/2`, `verify_gtin/2`) are *not* audited to the
  table — GTIN preview runs on every catalog search and would swamp it. They
  are retried on transient failures and logged via `Logger` instead.

  Functions take an `ThamaniDawa.Accounts.Scope` because an audit row needs
  both the organization and the user who triggered the call.
  """

  require Logger

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Gs1Api.Client
  alias ThamaniDawa.Gs1Api.Error
  alias ThamaniDawa.Gs1Api.Request
  alias ThamaniDawa.Repo

  import Ecto.Query, warn: false

  @create_sscc "/api/create_sscc"
  @get_sscc "/api/get_sscc"
  @create_serialised "/api/create_serialised_datamatrix"
  @getbarcode "/api/getbarcode_v2"

  @doc """
  Mints an SSCC for one or more batch entries (§4.1).

  `batch_info` may be a single map or a list; GS1 shares one SSCC code across
  every entry in the list. Every key except `customer_part_number` is required
  by the API, and a missing one comes back as a `:missing_params` error rather
  than being caught locally — the API's copy is the copy we show.
  """
  @spec create_sscc(Scope.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create_sscc(%Scope{} = scope, params) do
    audited(scope, @create_sscc, params)
  end

  @doc """
  Generates serialised Data Matrix codes for a GTIN (§4.3).

  GS1 authorizes `trade_item_qty + trunc(trade_item_qty / shipper_qty)` serials
  against the organization's plan before issuing anything, and remains the sole
  enforcer of that allowance (§6) — a rejection here is authoritative and its
  message is shown verbatim.
  """
  @spec create_serialised_datamatrix(Scope.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create_serialised_datamatrix(%Scope{} = scope, params) do
    audited(scope, @create_serialised, params)
  end

  @doc "Fetches an already-issued SSCC with its batch entries and label data (§4.2)."
  @spec get_sscc(Scope.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_sscc(%Scope{}, sscc) when is_binary(sscc) do
    Client.post(@get_sscc, %{sscc: sscc}, idempotent?: true)
  end

  @doc """
  Verifies a GTIN against the GS1 platform (§4.4).

  Preview only: per §2.4.9 the result is *not* persisted here. A catalog row is
  written at save time by `ThamaniDawa.SerialCatalog.ensure_item/2`.

  The GTIN is sent in the 13-digit form the platform requires, even though we
  hold canonical GTIN-14 locally.
  """
  @spec verify_gtin(Scope.t(), String.t()) :: {:ok, map()} | {:error, Error.t() | :invalid_gtin}
  def verify_gtin(%Scope{}, gtin) when is_binary(gtin) do
    with {:ok, gtin13} <- ThamaniDawa.Gtin.to_gtin13(gtin) do
      Client.post(@getbarcode, %{barcode: gtin13}, idempotent?: true)
    end
  end

  @doc "Lists an organization's GS1 call audit rows, newest first."
  def list_requests(organization_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Repo.all(
      from r in Request,
        where: r.organization_id == ^organization_id,
        order_by: [desc: r.inserted_at, desc: r.id],
        limit: ^limit
    )
  end

  @doc """
  Lists calls that were recorded but never settled.

  These are the rows that need a human: the request may or may not have minted
  a code on the GS1 side, and only `get_sscc/2` against the issuing member can
  tell you which (§4.5).
  """
  def list_pending_requests(organization_id) do
    Repo.all(
      from r in Request,
        where: r.organization_id == ^organization_id and r.status == :pending,
        order_by: [asc: r.inserted_at]
    )
  end

  # A generation call: record the attempt, make it, then settle the record.
  defp audited(%Scope{} = scope, endpoint, params) do
    request_id = Ecto.UUID.generate()
    payload = params |> normalize_payload() |> Map.put("request_id", request_id)

    case insert_pending(scope, endpoint, request_id, payload) do
      {:ok, record} ->
        endpoint
        |> Client.post(payload)
        |> settle(record)

      {:error, changeset} ->
        Logger.error("Could not record GS1 request for #{endpoint}: #{inspect(changeset.errors)}")
        {:error, Error.not_configured()}
    end
  end

  defp insert_pending(%Scope{} = scope, endpoint, request_id, payload) do
    %Request{}
    |> Request.changeset(%{
      organization_id: scope.organization_id,
      user_id: scope.user && scope.user.id,
      endpoint: endpoint,
      request_id: request_id,
      payload_digest: digest(payload),
      status: :pending
    })
    |> Repo.insert()
  end

  defp settle({:ok, body} = result, record) do
    update_record(record, %{status: :succeeded, response_summary: summarize(body)})
    result
  end

  defp settle({:error, %Error{} = error} = result, record) do
    update_record(record, %{
      status: :failed,
      error_message: error.message,
      response_summary: %{"reason" => to_string(error.reason), "status" => error.status}
    })

    result
  end

  defp update_record(record, attrs) do
    record
    |> Request.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        updated

      # The call itself already happened; failing to annotate the audit row
      # must not turn a successful generation into an error for the caller.
      {:error, changeset} ->
        Logger.error("Could not settle GS1 request #{record.request_id}: #{inspect(changeset.errors)}")
        record
    end
  end

  # Serial lists run to six figures — keep the shape, drop the bulk.
  defp summarize(body) when is_map(body) do
    body
    |> Enum.map(fn {key, value} -> {to_string(key), summarize_value(value)} end)
    |> Map.new()
  end

  defp summarize(body), do: %{"body" => summarize_value(body)}

  defp summarize_value(value) when is_list(value), do: %{"count" => length(value)}
  defp summarize_value(value) when is_map(value), do: summarize(value)
  defp summarize_value(value) when is_binary(value) and byte_size(value) > 200, do: "…"
  defp summarize_value(value), do: value

  defp digest(payload) do
    :sha256
    |> :crypto.hash(Jason.encode!(payload))
    |> Base.encode16(case: :lower)
  end

  defp normalize_payload(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end
end
