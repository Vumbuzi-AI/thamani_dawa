defmodule ThamaniDawa.Manufacturing.ProductSyncWorker do
  @moduledoc """
  Oban worker that pulls an organization's GTIN product catalogue from the
  GS1 member API (`ThamaniDawa.Manufacturing.sync_products/1`). Enqueued
  automatically when a manufacturing site is added, so the catalogue is
  ready without a manual "Sync" click. GS1 outages retry via Oban.
  """

  use Oban.Worker, queue: :gs1, max_attempts: 5, unique: [period: 60, keys: [:organization_id]]

  alias ThamaniDawa.Manufacturing

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_id" => organization_id}}) do
    case Manufacturing.sync_products(organization_id) do
      {:ok, _count} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Enqueues a product sync for the organization."
  def enqueue(organization_id) do
    %{organization_id: organization_id} |> new() |> Oban.insert()
  end
end
