defmodule ThamaniDawa.ScanEvents do
  @moduledoc "Records and reads the `scan_events` traceability log (§4.6)."

  import Ecto.Query, warn: false

  alias ThamaniDawa.Repo
  alias ThamaniDawa.ScanEvent

  @doc "Logs a scan event under the given organization. `attrs` needs `:gtin` and `:event_type` at minimum."
  def log_scan_event(organization_id, attrs) when is_integer(organization_id) do
    %ScanEvent{}
    |> ScanEvent.changeset(Map.put(attrs, :organization_id, organization_id))
    |> Repo.insert()
  end

  @doc "Lists an organization's scan events for a given GTIN/batch_no, most recent first."
  def list_scan_events_for_batch(organization_id, gtin, batch_no) do
    Repo.all(
      from e in ScanEvent,
        where: e.organization_id == ^organization_id,
        where: e.gtin == ^gtin and e.batch_no == ^batch_no,
        order_by: [desc: e.inserted_at, desc: e.id]
    )
  end
end
