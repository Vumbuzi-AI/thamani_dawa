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
  `ExGtin.normalize/1`. A no-op when the field wasn't changed; adds an
  error when the code fails the GS1 check digit.
  """
  def validate_gtin(changeset, field \\ :gtin) do
    case get_change(changeset, field) do
      nil ->
        changeset

      gtin ->
        case ExGtin.normalize(gtin) do
          {:ok, normalized} -> put_change(changeset, field, normalized)
          {:error, _reason} -> add_error(changeset, field, "is not a valid GTIN")
        end
    end
  end

  @doc "Generates a valid GTIN by appending a GS1 check digit to `base_code`."
  def generate(base_code), do: ExGtin.generate(base_code)
end
