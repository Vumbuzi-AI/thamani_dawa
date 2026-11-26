defmodule ThamaniDawa.Manufacturing.IdentifierAllocationWorker do
  @moduledoc "Allocates one persisted GS1 generation intent without blind retries."

  # One generation operation is intentionally queued more than once across
  # its lifecycle: first for product serials, then again after each shipper
  # reaches capacity. The row-locked allocation state in Operations is the
  # idempotency guard; making the Oban job unique by operation_id would
  # suppress those later, valid phases.
  use Oban.Worker, queue: :gs1, max_attempts: 1

  alias ThamaniDawa.Manufacturing.Operations

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"operation_id" => operation_id}}) do
    case Operations.allocate_identifiers(operation_id) do
      {:ok, _operation} -> :ok
      {:error, :not_actionable} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
