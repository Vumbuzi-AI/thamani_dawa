defmodule ThamaniDawa.PbbNumber do
  @moduledoc """
  Normalizes and validates Kenya PBB (Pharmacy and Poisons Board) premise and superintendent license numbers.
  """

  # Accepts PPB/PRM/..., PPB-..., LIC-..., P/..., PT/..., or numeric licenses
  @pbb_regex ~r/^(PPB[\/\-](PRM|PREM)?[\/\-]?[A-Z0-9\/]+|P\/\d+|PT\/\d+|LIC\-\d+|\d{3,10})$/i

  @doc """
  Normalizes a raw PBB input by stripping whitespace and converting to uppercase.
  """
  @spec normalize(String.t() | nil) :: String.t()
  def normalize(nil), do: ""

  def normalize(raw) when is_binary(raw) do
    raw
    |> String.trim()
    |> String.upcase()
    |> String.replace(~r/\s+/, "")
  end

  @doc """
  Validates if a given raw PBB input matches valid PBB formats.
  Returns `{:ok, normalized_pbb}` or `{:error, :invalid_format}`.
  """
  @spec validate_format(String.t() | nil) :: {:ok, String.t()} | {:error, :invalid_format}
  def validate_format(nil), do: {:error, :invalid_format}

  def validate_format(raw) when is_binary(raw) do
    normalized = normalize(raw)

    if normalized != "" and String.match?(normalized, @pbb_regex) do
      {:ok, normalized}
    else
      {:error, :invalid_format}
    end
  end
end
