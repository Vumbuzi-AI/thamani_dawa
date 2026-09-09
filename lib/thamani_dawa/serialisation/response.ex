defmodule ThamaniDawa.Serialisation.Response do
  @moduledoc """
  Reads the identifiers out of a GS1 generation response.

  `gs1_admin` wraps its payloads differently depending on the endpoint and how
  the member is registered, so each field is looked for under every shape the
  API has been observed to use rather than one assumed path. What is *not*
  tolerated is a missing identifier: `{:error, :no_sscc_issued}` is returned so
  the caller records a failed run, because inventing a code locally would be a
  breach of §2.4.1.
  """

  alias ThamaniDawa.Gs1Api.Error

  @doc """
  The SSCC issued by `POST /api/create_sscc` (§4.1), as
  `%{code:, extension_digit:, image:}`.
  """
  @spec sscc(map()) :: {:ok, map()} | {:error, Error.t()}
  def sscc(body) do
    payload = unwrap(body)

    case dig_code(payload, ["sscc", "code", "sscc_code"]) do
      nil ->
        {:error, Error.unexpected_response()}

      code ->
        {:ok,
         %{
           code: code,
           extension_digit: string_at(payload, ["extension_digit", "extensionDigit"]),
           image: string_at(payload, ["image", "image_path", "datamatrix", "barcode_image"])
         }}
    end
  end

  @doc """
  The pallet SSCC, its shippers and their primary serials from
  `POST /api/create_serialised_datamatrix` (§4.3).

  A response with no shipper groupings but a flat serial list is still valid —
  it is one implicit shipper holding the whole run.
  """
  @spec serialised(map()) :: {:ok, map()} | {:error, Error.t()}
  def serialised(body) do
    payload = unwrap(body)

    case dig_code(payload, ["sscc", "pallet_sscc", "palletSscc"]) do
      nil ->
        {:error, Error.unexpected_response()}

      pallet ->
        {:ok,
         %{
           pallet_sscc: pallet,
           extension_digit: string_at(payload, ["extension_digit", "extensionDigit"]),
           shippers: shippers(payload, pallet)
         }}
    end
  end

  defp shippers(payload, pallet) do
    case list_at(payload, ["shippers", "shipper_serials", "shipper_groups", "groups"]) do
      [] ->
        case list_at(payload, ["primary_serials", "serials"]) do
          [] -> []
          serials -> [%{sscc: pallet, serial: nil, primary_serials: to_serials(serials)}]
        end

      groups ->
        Enum.map(groups, fn group ->
          %{
            sscc: dig_code(group, ["sscc", "shipper_sscc"]),
            serial: string_at(group, ["serial", "shipper_serial"]),
            primary_serials:
              group |> list_at(["primary_serials", "serials"]) |> to_serials()
          }
        end)
        |> Enum.reject(&is_nil(&1.sscc))
    end
  end

  # A serial may arrive as a bare string or as an object carrying the payload
  # alongside it; either way only the serial itself is stored — the Data Matrix
  # is deterministic once the serial is known (§2.5).
  defp to_serials(values) do
    values
    |> Enum.map(fn
      value when is_binary(value) -> value
      value when is_integer(value) -> Integer.to_string(value)
      %{} = value -> string_at(value, ["serial", "primary_serial", "code"])
      _other -> nil
    end)
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  # An SSCC may be a bare string or an object with the code nested inside it.
  defp dig_code(payload, keys) do
    Enum.find_value(keys, fn key ->
      case Map.get(payload, key) do
        value when is_binary(value) and value != "" -> value
        value when is_integer(value) -> Integer.to_string(value)
        %{} = nested -> string_at(nested, ["sscc", "code", "value"])
        _other -> nil
      end
    end)
  end

  defp string_at(payload, keys) when is_map(payload) do
    Enum.find_value(keys, fn key ->
      case Map.get(payload, key) do
        value when is_binary(value) and value != "" -> value
        value when is_integer(value) -> Integer.to_string(value)
        _other -> nil
      end
    end)
  end

  defp string_at(_payload, _keys), do: nil

  defp list_at(payload, keys) when is_map(payload) do
    Enum.find_value(keys, [], fn key ->
      case Map.get(payload, key) do
        value when is_list(value) and value != [] -> value
        _other -> nil
      end
    end)
  end

  defp list_at(_payload, _keys), do: []

  defp unwrap(%{"data" => %{} = inner}), do: inner
  defp unwrap(%{"result" => %{} = inner}), do: inner
  defp unwrap(%{} = body), do: body
  defp unwrap(_body), do: %{}
end
