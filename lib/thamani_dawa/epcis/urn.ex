defmodule ThamaniDawa.Epcis.Urn do
  @moduledoc """
  EPC URN construction for PPB Track & Trace events (docs/PPB_TNT_INTEGRATION.md §3).

  Every function validates the GS1 check digit before splitting, so a mistyped
  identifier fails at build time instead of as a Hub-side hard reject
  (`INVALID_GS1_IDENTIFIER`). Splitting a digit string into company prefix and
  reference needs the owner's GS1 Company Prefix length; when the owner is
  unknown (foreign GTINs, partner GLNs) callers fall back to the configured
  `default_prefix_length` and must treat registry-match warnings as expected.
  """

  alias ThamaniDawa.GS1.Sscc

  @serial_pattern ~r/^[\x21-\x22\x25-\x2F\x30-\x39\x3A-\x3F\x41-\x5A\x5F\x61-\x7A]{1,20}$/

  @doc """
  Builds an SGTIN EPC URN from a GTIN-14 and a serial.

      iex> ThamaniDawa.Epcis.Urn.sgtin("00614141107346", "1001", 7)
      {:ok, "urn:epc:id:sgtin:0614141.010734.1001"}

      iex> ThamaniDawa.Epcis.Urn.sgtin("00614141107347", "1001", 7)
      {:error, :invalid_check_digit}

      iex> ThamaniDawa.Epcis.Urn.sgtin("00614141107346", "", 7)
      {:error, :invalid_serial}
  """
  def sgtin(gtin14, serial, prefix_length) do
    with {:ok, digits} <- checked_digits(gtin14, 14),
         :ok <- validate_serial(serial),
         {:ok, {prefix, item_ref}} <- split_gtin(digits, prefix_length) do
      {:ok, "urn:epc:id:sgtin:#{prefix}.#{item_ref}.#{serial}"}
    end
  end

  @doc """
  Builds an LGTIN (lot-level) class URN from a GTIN-14 and a lot number.

      iex> ThamaniDawa.Epcis.Urn.lgtin("00614141107346", "LOT123", 7)
      {:ok, "urn:epc:class:lgtin:0614141.010734.LOT123"}
  """
  def lgtin(gtin14, lot, prefix_length) do
    with {:ok, digits} <- checked_digits(gtin14, 14),
         :ok <- validate_serial(lot),
         {:ok, {prefix, item_ref}} <- split_gtin(digits, prefix_length) do
      {:ok, "urn:epc:class:lgtin:#{prefix}.#{item_ref}.#{lot}"}
    end
  end

  @doc """
  Builds an SSCC EPC URN from an 18-digit SSCC.

      iex> ThamaniDawa.Epcis.Urn.sscc("006141411234567890", 7)
      {:ok, "urn:epc:id:sscc:0614141.0123456789"}

      iex> ThamaniDawa.Epcis.Urn.sscc("006141411234567894", 7)
      {:error, :invalid_check_digit}
  """
  def sscc(sscc18, prefix_length) do
    with {:ok, digits} <- checked_digits(sscc18, 18),
         :ok <- validate_prefix_length(prefix_length, 17) do
      <<extension::binary-size(1), rest::binary>> = binary_part(digits, 0, 17)
      prefix = binary_part(rest, 0, prefix_length)
      serial_ref = binary_part(rest, prefix_length, 16 - prefix_length)
      {:ok, "urn:epc:id:sscc:#{prefix}.#{extension}#{serial_ref}"}
    end
  end

  @doc """
  Builds a facility-level SGLN EPC URN from a GLN-13.

      iex> ThamaniDawa.Epcis.Urn.sgln("0614141000012", 7)
      {:ok, "urn:epc:id:sgln:0614141.00001.0"}

      iex> ThamaniDawa.Epcis.Urn.sgln("0614141000013", 7)
      {:error, :invalid_check_digit}
  """
  def sgln(gln13, prefix_length) do
    with {:ok, digits} <- checked_digits(gln13, 13),
         :ok <- validate_prefix_length(prefix_length, 12) do
      body = binary_part(digits, 0, 12)
      prefix = binary_part(body, 0, prefix_length)
      location_ref = binary_part(body, prefix_length, 12 - prefix_length)
      {:ok, "urn:epc:id:sgln:#{prefix}.#{location_ref}.0"}
    end
  end

  @doc """
  Picks the prefix length to split `identifier` with: the organization's own
  prefix length when the identifier was issued under it, otherwise the
  configured default.

      iex> ThamaniDawa.Epcis.Urn.prefix_length_for("0614141000012", "0614141")
      7
  """
  def prefix_length_for(identifier, org_prefix) do
    if is_binary(org_prefix) and org_prefix != "" and leading_prefix?(identifier, org_prefix) do
      String.length(org_prefix)
    else
      default_prefix_length()
    end
  end

  def default_prefix_length do
    :thamani_dawa
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:default_prefix_length, 7)
  end

  defp leading_prefix?(identifier, org_prefix) when byte_size(identifier) in [14, 18] do
    <<_indicator_or_extension::binary-size(1), rest::binary>> = identifier
    String.starts_with?(rest, org_prefix)
  end

  defp leading_prefix?(identifier, org_prefix), do: String.starts_with?(identifier, org_prefix)

  defp checked_digits(value, length) when is_binary(value) do
    digits = String.trim(value)

    cond do
      not Regex.match?(~r/^\d+$/, digits) -> {:error, :not_numeric}
      String.length(digits) != length -> {:error, :invalid_length}
      not check_digit_valid?(digits) -> {:error, :invalid_check_digit}
      true -> {:ok, digits}
    end
  end

  defp checked_digits(_value, _length), do: {:error, :not_numeric}

  defp check_digit_valid?(digits) do
    {payload, check} = String.split_at(digits, -1)
    Integer.to_string(Sscc.mod10_check_digit(payload)) == check
  end

  defp split_gtin(digits, prefix_length) do
    with :ok <- validate_prefix_length(prefix_length, 13) do
      <<indicator::binary-size(1), rest::binary>> = binary_part(digits, 0, 13)
      prefix = binary_part(rest, 0, prefix_length)
      item_ref = binary_part(rest, prefix_length, 12 - prefix_length)
      {:ok, {prefix, indicator <> item_ref}}
    end
  end

  defp validate_prefix_length(length, max)
       when is_integer(length) and length >= 6 and length < max,
       do: :ok

  defp validate_prefix_length(_length, _max), do: {:error, :invalid_prefix_length}

  defp validate_serial(serial) when is_binary(serial) do
    if Regex.match?(@serial_pattern, serial), do: :ok, else: {:error, :invalid_serial}
  end

  defp validate_serial(_serial), do: {:error, :invalid_serial}
end
