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

  def reason(conn, reason) do
    {status, code, message} = reason_details(reason)
    error(conn, status, code, message)
  end

  def field_errors(changeset) do
    # Only interpolate placeholders the message actually uses: options such
    # as an Ecto.Enum cast error's `:type` are tuples with no string form.
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, &interpolate(&1, &2, opts))
    end)
  end

  defp interpolate(placeholder, key, opts) do
    case Enum.find(opts, fn {opt, _value} -> Atom.to_string(opt) == key end) do
      {_opt, value} -> to_string(value)
      nil -> placeholder
    end
  end

  defp reason_details(:bad_request),
    do: {400, "bad_request", "The request is missing a required value."}

  defp reason_details(:invalid_credentials),
    do: {401, "invalid_credentials", "Invalid email or password."}

  defp reason_details(:invalid_token), do: {401, "invalid_token", "Sign in again."}
  defp reason_details(:unauthorized), do: {401, "unauthorized", "Sign in again."}

  defp reason_details(:account_inactive),
    do: {403, "account_inactive", "This account is disabled."}

  defp reason_details(:forbidden), do: {403, "forbidden", "You cannot do that."}

  defp reason_details(:not_assigned),
    do: {403, "not_assigned", "You are not assigned to that site."}

  defp reason_details(:not_found), do: {404, "not_found", "Not found."}

  defp reason_details(:idempotency_conflict),
    do:
      {409, "idempotency_conflict",
       "That idempotency key was already used with a different request."}

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

  defp reason_details(:site_id_required),
    do: {422, "site_id_required", "Send the site_id of the site this stock is for."}

  defp reason_details(:invalid_site_id),
    do: {422, "invalid_site_id", "site_id must be a whole number."}

  defp reason_details(:quantity_required),
    do: {422, "quantity_required", "Enter how many units to move (quantity)."}

  defp reason_details(:invalid_quantity),
    do: {422, "invalid_quantity", "quantity must be a whole number."}

  defp reason_details(:invalid_dispatch_quantity),
    do: {422, "invalid_quantity", "quantity must be more than zero."}

  defp reason_details(:already_dispatched),
    do:
      {422, "already_dispatched",
       "This batch is already at a site. Only warehouse stock can be dispatched."}

  defp reason_details(:nothing_to_dispatch),
    do: {422, "insufficient_stock", "This batch has no stock left to move."}

  defp reason_details(:not_draft),
    do: {422, "not_draft", "This can only be changed while it is a draft."}

  defp reason_details(:not_pending),
    do: {422, "not_pending", "Only a pending request can do that."}

  defp reason_details(:not_approvable),
    do: {422, "not_approvable", "Only a draft or pending request can be approved."}

  defp reason_details(:not_requester),
    do: {403, "not_requester", "Only the person who started this can do that."}

  defp reason_details(:no_counted_items),
    do: {422, "no_counted_items", "Count at least one batch before submitting."}

  defp reason_details(:no_items),
    do: {422, "no_items", "Add at least one batch before submitting."}

  defp reason_details(:not_expired),
    do: {422, "not_expired", "Only a batch past its expiry date can be written off."}

  defp reason_details(:partial_expiry),
    do: {422, "partial_expiry", "An expiry write-off must take the whole remaining quantity."}

  defp reason_details(:no_supplier),
    do: {422, "no_supplier", "This batch has no supplier recorded, so it cannot be returned."}

  defp reason_details({:stock_changed, _item_id}),
    do: {409, "stock_changed", "Stock moved since this was added. Review the quantities."}

  defp reason_details(:not_authorized), do: {403, "forbidden", "You cannot do that."}

  defp reason_details(reason) when is_atom(reason) do
    {422, Atom.to_string(reason), "The request could not be completed."}
  end

  defp reason_details(_reason) do
    {422, "validation_failed", "The request could not be completed."}
  end
end
