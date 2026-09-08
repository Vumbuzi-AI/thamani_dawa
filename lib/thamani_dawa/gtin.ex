defmodule ThamaniDawa.Gtin do
  @moduledoc """
  Wires up `ex_gtin` (§3 of project.md) for the GTINs entering the catalog
  via `products.gtin` and `batches.gtin`. Every code is normalized to
  canonical GTIN-14 (zero-padded) so a GTIN-12 UPC and its GTIN-14 form
  never look like two different products, and the GS1 check digit is
  verified before the code is ever stored.
  """

  import Ecto.Changeset

  @doc """
  Validates and normalizes `field` (`:gtin` by default) on a changeset via
  `ExGtin.normalize/1`. A no-op when the field wasn't changed; adds an error
  when the code fails the GS1 check digit.

  `ExGtin.normalize/1` assumes every character is a digit and raises
  `ArgumentError` if it isn't — so a non-numeric code (letters, punctuation)
  is rejected here first, before ever reaching it, rather than crashing.
  """
  def validate_gtin(changeset, field \\ :gtin) do
    case get_change(changeset, field) do
      nil -> changeset
      gtin -> put_normalized_gtin(changeset, field, gtin)
    end
  end

  defp put_normalized_gtin(changeset, field, gtin) do
    case normalize(gtin) do
      {:ok, normalized} -> put_change(changeset, field, normalized)
      {:error, _reason} -> add_error(changeset, field, "is not a valid GTIN")
    end
  end

  @doc """
  Validates and normalizes a raw GTIN string to canonical GTIN-14 form, outside of a changeset
  (e.g. for an external lookup called with a raw search-box value rather than a schema field).
  Returns `{:error, :invalid_gtin}` for non-numeric input, `nil`, or a failed GS1 check digit,
  rather than letting `ExGtin.normalize/1` raise on non-numeric input or `=~/2` raise on `nil`.
  """
  def normalize(gtin) when is_binary(gtin) do
    if digits_only?(gtin) do
      case ExGtin.normalize(gtin) do
        {:ok, normalized} -> {:ok, normalized}
        {:error, _reason} -> {:error, :invalid_gtin}
      end
    else
      {:error, :invalid_gtin}
    end
  end

  def normalize(_gtin), do: {:error, :invalid_gtin}

  defp digits_only?(value), do: value =~ ~r/^\d+$/

  @doc "Generates a valid GTIN by appending a GS1 check digit to `base_code`."
  def generate(base_code), do: ExGtin.generate(base_code)

  @doc """
  Renders a GTIN in the 13-digit form the `gs1_admin` API insists on
  (serialisation.md §4.3: "`barcode` must be exactly 13 digits").

  We store canonical GTIN-14 locally, which for an EAN-13 is the same code with
  a leading zero — dropping it is lossless. A code that is genuinely 14
  significant digits (an ITF-14 outer case) has no 13-digit form and returns
  `{:error, :invalid_gtin}` rather than being silently truncated.
  """
  def to_gtin13(gtin) do
    with {:ok, "0" <> rest} <- normalize(gtin) do
      {:ok, rest}
    else
      {:ok, _fourteen_significant_digits} -> {:error, :invalid_gtin}
      {:error, reason} -> {:error, reason}
    end
  end
end
