defmodule ThamaniDawaWeb.Api.V1.ManufacturerFallback do
  @moduledoc """
  Error rendering for the manufacturer endpoints. Turns the Manufacturing
  and Distributor contexts' tagged errors into the API's error envelope and
  hands everything else to `ThamaniDawaWeb.Api.FallbackController`.
  """

  use ThamaniDawaWeb, :controller

  alias ThamaniDawaWeb.Api.FallbackController
  alias ThamaniDawaWeb.Api.Response

  def call(conn, {:error, {:invalid_state, status}}) do
    Response.error(conn, 409, "invalid_state", "This is #{status}.", %{status: status})
  end

  def call(conn, {:error, {:over_capacity, details}}) do
    Response.error(conn, 422, "over_capacity", "This exceeds the SSCC's capacity.", %{
      capacity: details.capacity,
      linked: details.linked,
      adding: details.adding
    })
  end

  def call(conn, {:error, {:invalid_items, items}}) do
    Response.error(conn, 422, "invalid_serials", "Some serials are not valid for this SSCC.", %{
      serials: Enum.map(items, &%{serial: &1.serial, validation_status: &1.validation_status})
    })
  end

  def call(conn, {:error, {:invalid, problems}}) when is_list(problems) do
    Response.error(conn, 422, "shipment_invalid", "Fix these before approving.", %{
      problems: Enum.map(problems, &problem/1)
    })
  end

  def call(conn, {:error, {:gs1, _reason}}) do
    Response.error(conn, 502, "gs1_unavailable", "The GS1 service could not complete this.")
  end

  def call(conn, {:error, {:billing, _reason}}) do
    Response.error(conn, 402, "billing", "Serialisation billing needs attention on the web.")
  end

  def call(conn, {:error, :no_ssccs}),
    do: Response.error(conn, 422, "no_ssccs", "Add at least one shipper first.")

  def call(conn, {:error, :missing_product}),
    do: Response.error(conn, 422, "missing_product", "No product matches this SSCC.")

  def call(conn, {:error, :reservation_missing}),
    do: Response.error(conn, 409, "reservation_missing", "Some units are no longer reserved.")

  def call(conn, {:error, :duplicate_serial}),
    do: Response.error(conn, 409, "duplicate_serial", "That serial has already been added.")

  def call(conn, {:error, :invalid_mode}),
    do: Response.error(conn, 422, "invalid_mode", "Mode must be stock or order.")

  def call(conn, {:error, :site_gln_required}),
    do:
      Response.error(
        conn,
        422,
        "site_gln_required",
        "Pick a manufacturing site with a GLN before generating serials."
      )

  def call(conn, {:error, {:fields, errors}}) do
    Response.error(conn, 422, "validation_failed", "Some fields are invalid.", %{
      fields:
        errors
        |> Enum.reverse()
        |> Enum.group_by(fn {field, _error} -> field end, fn {_field, {message, _opts}} ->
          message
        end)
    })
  end

  def call(conn, error), do: FallbackController.call(conn, error)

  defp problem(%{code: code, message: message}), do: %{code: to_string(code), message: message}
  defp problem(other), do: %{code: "invalid", message: inspect(other)}
end
