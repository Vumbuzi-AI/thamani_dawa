defmodule ThamaniDawa.Manufacturing.SerialGeneration do
  @moduledoc """
  Pure rules for the "+ Serial" wizard, shared by the manufacturer web
  portal and the JSON API.

  Make-to-stock (`"stock"`) mints primary serials for a batch. Make-to-order
  (`"order"`) also mints shipper SSCCs under one pallet and needs the
  From/To parties printed on the labels. Params are string-keyed, as they
  come from a form or a JSON body.
  """

  @max_primary_quantity 100
  @party_fields ~w(from_gln from_company_name from_address to_gln to_company_name to_address)

  def max_primary_quantity, do: @max_primary_quantity
  def party_fields, do: @party_fields

  @doc "The batch fields of a generation request."
  def batch_attrs(params), do: Map.take(params, ["batch_no", "production_date", "expiry_date"])

  @doc "The From/To party fields of a generation request."
  def parties(params), do: Map.take(params, @party_fields)

  @doc """
  Fills the From company name and address from the chosen facility, so they
  always match the From GLN.
  """
  def fill_from_facility(params, facilities) do
    case Enum.find(facilities, &(&1.gln == params["from_gln"])) do
      nil ->
        params

      facility ->
        params
        |> Map.put("from_company_name", facility.name || "")
        |> Map.put("from_address", facility.address || "")
    end
  end

  @doc "Puts a resolved To party's company name and address on the params."
  def put_to_party(params, party) do
    params
    |> Map.put("to_company_name", party.company || "")
    |> Map.put("to_address", party.address || "")
  end

  @doc """
  Validation errors as a keyword list of `{field, {message, []}}`, empty
  when the request is ready to generate.
  """
  def errors(params, mode) do
    []
    |> required_error(params, :batch_no, "Batch number")
    |> required_error(params, :production_date, "Production date")
    |> required_error(params, :expiry_date, "Expiry date")
    |> quantity_error(params, :primary_quantity, "Primary quantity", @max_primary_quantity)
    |> date_order_error(params)
    |> mode_errors(params, mode)
  end

  defp mode_errors(errors, params, "order") do
    errors
    |> quantity_error(params, :shipper_quantity, "Shipper quantity")
    |> shipper_not_over_primary_error(params)
    |> required_error(params, :from_gln, "From GLN")
    |> required_error(params, :from_company_name, "From company name")
    |> required_error(params, :from_address, "From address")
    |> required_error(params, :to_gln, "To GLN")
    |> required_error(params, :to_company_name, "To company name")
    |> required_error(params, :to_address, "To address")
  end

  defp mode_errors(errors, _params, _mode), do: errors

  defp required_error(errors, params, field, label) do
    if Map.get(params, Atom.to_string(field)) in [nil, ""],
      do: [{field, {"#{label} is required", []}} | errors],
      else: errors
  end

  defp quantity_error(errors, params, field, label, max \\ nil) do
    case Integer.parse(Map.get(params, Atom.to_string(field), "")) do
      {quantity, ""} when quantity > 0 ->
        if is_integer(max) and quantity > max,
          do: [{field, {"#{label} cannot exceed #{max}", []}} | errors],
          else: errors

      _other ->
        [{field, {"#{label} must be a positive integer", []}} | errors]
    end
  end

  defp shipper_not_over_primary_error(errors, params) do
    with {primary, ""} <- Integer.parse(Map.get(params, "primary_quantity", "")),
         {shipper, ""} <- Integer.parse(Map.get(params, "shipper_quantity", "")),
         true <- shipper > primary do
      [{:shipper_quantity, {"cannot exceed the primary quantity", []}} | errors]
    else
      _other -> errors
    end
  end

  defp date_order_error(errors, params) do
    with {:ok, production} <- Date.from_iso8601(Map.get(params, "production_date", "")),
         {:ok, expiry} <- Date.from_iso8601(Map.get(params, "expiry_date", "")),
         false <- Date.after?(expiry, production) do
      [{:expiry_date, {"must be after the production date", []}} | errors]
    else
      _other -> errors
    end
  end
end
