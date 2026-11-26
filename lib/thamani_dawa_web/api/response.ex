defmodule ThamaniDawaWeb.Api.Response do
  @moduledoc """
  JSON envelope for `/api/v1`.

  Success bodies are `%{"data" => ...}` plus optional `"meta"`. Errors are
  `%{"error" => %{"code", "message", "fields"}}`. Branch on `code`.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def data(conn, payload, status \\ 200) do
    conn
    |> put_status(status)
    |> json(%{data: payload})
  end

  def page(conn, entries, meta) do
    json(conn, %{data: entries, meta: meta})
  end

  def error(conn, status, code, message, extra \\ %{}) do
    body = Map.merge(%{code: code, message: message}, extra)

    conn
    |> put_status(status)
    |> json(%{error: body})
  end

  def changeset(conn, %Ecto.Changeset{} = changeset) do
    error(conn, 422, "validation_failed", "Some fields are invalid.", %{
      fields: field_errors(changeset)
    })
  end

  def reason(conn, {:account_locked, locked_until}) do
    extra =
      if match?(%DateTime{}, locked_until),
        do: %{locked_until: DateTime.to_iso8601(locked_until)},
        else: %{}

    error(conn, 423, "account_locked", "This account is locked. Try again later.", extra)
  end

  def reason(conn, reason) do
    {status, code, message} = reason_details(reason)
    error(conn, status, code, message)
  end

  def field_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp reason_details(:bad_request),
    do: {400, "bad_request", "The request is missing a required value."}

  defp reason_details(:device_required),
    do: {400, "bad_request", "Missing X-Device-Id."}

  defp reason_details(:invalid_credentials),
    do: {401, "invalid_credentials", "Invalid email or password."}

  defp reason_details(:invalid_token), do: {401, "invalid_token", "Sign in again."}
  defp reason_details(:unauthorized), do: {401, "unauthorized", "Sign in again."}

  defp reason_details(:account_inactive),
    do: {403, "account_inactive", "This account is disabled."}

  defp reason_details(:account_locked),
    do: {423, "account_locked", "This account is locked. Try again later."}

  defp reason_details(:rate_limited),
    do: {429, "rate_limited", "Too many attempts. Try again later."}

  defp reason_details(:forbidden), do: {403, "forbidden", "You cannot do that."}

  defp reason_details(:not_assigned),
    do: {403, "not_assigned", "You are not assigned to that site."}

  defp reason_details(:not_found), do: {404, "not_found", "Not found."}

  defp reason_details(:unknown_lot),
    do: {404, "not_found", "No batch on this line matches that code."}

  defp reason_details(:parties_required),
    do: {409, "parties_required", "Set From and To before opening a box."}

  defp reason_details(:no_unpacked),
    do: {409, "no_unpacked", "No loose serials on this batch."}

  defp reason_details(:already_claimed),
    do: {409, "already_claimed", "That serial is already in another box."}

  defp reason_details(:not_editable),
    do: {409, "not_editable", "This box is already saved."}

  defp reason_details(:idempotency_conflict),
    do:
      {409, "idempotency_conflict",
       "That idempotency key was already used with a different request."}

  defp reason_details(:invalid_gln),
    do: {422, "invalid_gln", "Enter a 13-digit GLN."}

  defp reason_details(:same_party),
    do: {422, "same_party", "From and To must be different."}

  defp reason_details(:wrong_batch),
    do: {422, "wrong_batch", "That serial is not from this batch."}

  defp reason_details(:not_unpacked),
    do: {422, "not_unpacked", "That serial is already packed."}

  defp reason_details(:unreadable),
    do: {422, "unreadable", "Could not read that scan."}

  defp reason_details(:empty_box),
    do: {422, "empty_box", "Scan at least one serial before saving."}

  defp reason_details(:out_of_stock),
    do: {422, "insufficient_stock", "There is not enough stock."}

  defp reason_details(:insufficient_quantity),
    do: {422, "insufficient_stock", "There is not enough stock."}

  defp reason_details(:insufficient_stock),
    do: {422, "insufficient_stock", "There is not enough stock."}

  defp reason_details(:invalid_gtin),
    do: {422, "invalid_gtin", "That is not a valid GTIN or GS1 scan."}

  defp reason_details(:site_required), do: {422, "site_required", "Choose a site first."}
  defp reason_details(:no_lines), do: {422, "validation_failed", "Add at least one line."}

  defp reason_details(:duplicate_products),
    do: {422, "validation_failed", "Each product can only appear once."}

  defp reason_details(:reason_required),
    do: {422, "validation_failed", "A reason is required to change a completed result."}

  defp reason_details(:unsupported_preparation_method),
    do:
      {422, "unsupported_preparation_method",
       "This batch can only be prepared during packing. Choose that option and try again."}

  defp reason_details(:serialization_not_completed),
    do:
      {422, "serialization_not_completed",
       "Generate product serials before creating shippers for this batch."}

  defp reason_details(:preparation_method_locked),
    do:
      {422, "preparation_method_locked",
       "This batch has already started packing. Refresh it and continue from the current step."}

  defp reason_details(:sscc_prerequisites_missing),
    do:
      {422, "sscc_prerequisites_missing",
       "A valid ship-from and ship-to GLN is needed before a shipper can be created."}

  defp reason_details(:sscc_unavailable),
    do: {503, "unavailable", "GS1 couldn't create the shipper label right now. Try again."}

  defp reason_details(:reconciliation_required),
    do:
      {422, "reconciliation_required",
       "We couldn't confirm whether GS1 created the label. Check your GS1 account before trying again."}

  defp reason_details(:not_actionable),
    do:
      {422, "not_actionable",
       "That step is no longer available. Refresh the batch and continue from the current step."}

  defp reason_details(:unconfigured),
    do:
      {422, "unconfigured",
       "GS1 isn't set up for your organization. Add your GS1 key in organization settings."}

  defp reason_details(:unavailable),
    do: {503, "unavailable", "We couldn't reach GS1. Try again in a moment."}

  defp reason_details(:unknown_serial),
    do: {422, "unknown_serial", "That serial is not in this batch."}

  defp reason_details(:already_aggregated),
    do: {422, "already_aggregated", "That item is already packed."}

  defp reason_details(:unknown_shipper),
    do: {422, "unknown_shipper", "No shipper with that label was found."}

  defp reason_details(:no_shippers_captured),
    do: {422, "no_shippers_captured", "Scan at least one shipper before continuing."}

  defp reason_details(:capacity_not_reached),
    do: {422, "capacity_not_reached", "Scan more items before finishing this shipper."}

  defp reason_details(:capacity_reached),
    do: {422, "capacity_reached", "This shipper is full. Request its label first."}

  defp reason_details(:parent_mismatch),
    do: {422, "parent_mismatch", "That label does not match the one on this batch."}

  defp reason_details(:invalid_scan),
    do: {422, "invalid_scan", "That code could not be used here. Scan it again."}

  defp reason_details(:duplicate_scan),
    do: {422, "duplicate_scan", "That item has already been scanned."}

  defp reason_details(:invalid_product_identifier),
    do: {422, "invalid_product_identifier", "That product code is not valid for this batch."}

  defp reason_details(:wrong_product_or_batch),
    do: {422, "wrong_product_or_batch", "That item belongs to a different product or batch."}

  defp reason_details(:invalid_sscc),
    do: {422, "invalid_sscc", "That shipper label is not valid."}

  defp reason_details(:shipper_in_transit),
    do: {422, "shipper_in_transit", "That shipper is already on a shipment."}

  defp reason_details(:shipper_not_completed),
    do: {422, "shipper_not_completed", "That shipper has not been packed yet."}

  defp reason_details(:different_destination),
    do: {422, "different_destination", "That shipper is going to a different destination."}

  defp reason_details(:no_available_sscc),
    do: {422, "no_available_sscc", "There is no shipper label available right now."}

  defp reason_details(:batch_not_ready),
    do: {422, "batch_not_ready", "This batch is not ready for that step yet."}

  defp reason_details(:shipper_preparation_required),
    do: {422, "shipper_preparation_required", "Prepare this batch for shipper packing first."}

  defp reason_details(:invalid_session_stage),
    do:
      {422, "invalid_session_stage",
       "This step is no longer available. Refresh the batch and continue from the current step."}

  defp reason_details(:active_session_exists),
    do: {422, "active_session_exists", "This batch already has an active packing session."}

  defp reason_details(:batch_not_found),
    do: {404, "not_found", "That batch is no longer available."}

  defp reason_details(:missing_serials),
    do: {422, "missing_serials", "GS1 returned no serials for this batch. Try again."}

  defp reason_details(:not_reconcilable),
    do: {422, "not_reconcilable", "This batch does not need that check. Refresh it and continue."}

  defp reason_details(reason) when is_atom(reason) do
    {422, Atom.to_string(reason), "The request could not be completed."}
  end

  defp reason_details(_reason) do
    {422, "validation_failed", "The request could not be completed."}
  end
end
