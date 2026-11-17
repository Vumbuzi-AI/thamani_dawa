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
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
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

  defp reason_details(reason) when is_atom(reason) do
    {422, Atom.to_string(reason), "The request could not be completed."}
  end

  defp reason_details(_reason) do
    {422, "validation_failed", "The request could not be completed."}
  end
end
