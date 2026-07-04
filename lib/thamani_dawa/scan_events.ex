defmodule ThamaniDawa.ScanEvents do
  @moduledoc """
  Traceability log (§4.6): one `scan_events` row per GS1 scan across the
  receive/dispense/lab-consumption/transfer workflows (§9), tying the
  scanned GTIN/batch/GLN back to whichever record it confirmed
  (`reference_id`) and who scanned it (`user_id`). `event_type` doubles as
  the discriminator for what `reference_id` points to — `dispensed_items`
  on `dispense`, `batches` on `receipt`, `lab_consumable_usage` on
  `lab_consumption`, `stock_transfers` on `transfer_out`/`transfer_in`.
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.GS1Decoder
  alias ThamaniDawa.Repo
  alias ThamaniDawa.ScanEvents.ScanEvent

  @event_types ScanEvent.event_types()

  @doc "Lists an organization's scan events."
  def list_scan_events(organization_id) do
    Repo.all(from e in ScanEvent, where: e.organization_id == ^organization_id)
  end

  @doc "Gets a single scan event scoped to an organization. Raises if not found."
  def get_scan_event!(organization_id, id) do
    Repo.get_by!(ScanEvent, id: id, organization_id: organization_id)
  end

  @doc "Creates a scan event under the given organization."
  def create_scan_event(organization_id, attrs) when is_integer(organization_id) do
    %ScanEvent{}
    |> ScanEvent.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.insert()
  end

  @doc """
  Decodes a raw GS1 scan (`ThamaniDawa.GS1Decoder.parse/1`) and logs it as a
  `scan_events` row of the given `event_type`, tied back to whichever record
  the scan confirmed (`reference_id`) and who scanned it (`user_id`) — e.g.
  the `dispensed_items` row on a dispense scan-to-verify, or the `batches`
  row on a stock receipt. Returns `{:error, reason}` if the scanned payload
  doesn't parse (see `ThamaniDawa.GS1Decoder.parse/1`).
  """
  def log_scan_event(organization_id, event_type, reference_id, user_id, scanned_gs1_data)
      when is_integer(organization_id) and event_type in @event_types and is_binary(scanned_gs1_data) do
    with {:ok, %{gtin: gtin, batch_no: batch_no, gln: gln}} <- GS1Decoder.parse(scanned_gs1_data) do
      create_scan_event(organization_id, %{
        gtin: gtin,
        batch_no: batch_no,
        gln: gln,
        event_type: event_type,
        reference_id: reference_id,
        user_id: user_id
      })
    end
  end
end
