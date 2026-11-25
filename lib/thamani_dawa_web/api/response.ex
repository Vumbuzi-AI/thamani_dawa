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

  defp reason_details(reason) when is_atom(reason) do
    {422, Atom.to_string(reason), "The request could not be completed."}
  end

  defp reason_details(_reason) do
    {422, "validation_failed", "The request could not be completed."}
  end
end
