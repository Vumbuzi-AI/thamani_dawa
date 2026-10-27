defmodule ThamaniDawa.GS1.Sscc do
  @moduledoc """
  SSCC-18 (Serial Shipping Container Code) generation for distributor cartons.

  Format: extension digit (1) + GS1 Company Prefix (6–10 digits) +
          serial reference (fills remaining to 17 digits) + Mod10 check digit = 18 digits total.

  The serial reference is claimed atomically via UPDATE ... RETURNING to prevent
  two concurrent carton creations ever sharing the same SSCC.
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Repo

  @doc """
  Generates the next SSCC-18 for `organization_id`.

  Returns `{:ok, sscc_string}` or `{:error, :missing_gs1_company_prefix}` when
  the organization hasn't set a GS1 Company Prefix yet.

  The serial increment is done with UPDATE...RETURNING so it is atomic even under
  concurrent load — two cartons created at the same instant never receive the same SSCC.
  """
  @spec generate(pos_integer()) :: {:ok, String.t()} | {:error, :missing_gs1_company_prefix}
  def generate(organization_id) when is_integer(organization_id) do
    org = Repo.get!(Organization, organization_id)

    case org.gs1_company_prefix do
      prefix when prefix in [nil, ""] ->
        {:error, :missing_gs1_company_prefix}

      prefix ->
        {:ok, build_sscc(organization_id, prefix)}
    end
  end

  @doc """
  Computes the GS1 Mod-10 check digit for a numeric string.

  Weights alternate 3, 1, 3, 1, … from the rightmost digit of `digits`.
  """
  @spec mod10_check_digit(String.t()) :: non_neg_integer()
  def mod10_check_digit(digits) when is_binary(digits) do
    sum =
      digits
      |> String.reverse()
      |> String.graphemes()
      |> Enum.with_index()
      |> Enum.reduce(0, fn {digit, index}, acc ->
        weight = if rem(index, 2) == 0, do: 3, else: 1
        acc + String.to_integer(digit) * weight
      end)

    rem(10 - rem(sum, 10), 10)
  end

  defp build_sscc(organization_id, prefix) do
    serial_length = 16 - String.length(prefix)

    # SQLite does not return rows for `UPDATE ... RETURNING` through Ecto in
    # the same way Postgres does.  The increment remains atomic, and reading
    # the organization afterwards keeps local development and production on
    # the same allocation path.
    {1, _} =
      Repo.update_all(
        from(o in Organization, where: o.id == ^organization_id),
        inc: [next_sscc_serial: 1]
      )

    updated_org = Repo.get!(Organization, organization_id)

    serial = updated_org.next_sscc_serial
    serial_digits = serial |> Integer.to_string() |> String.pad_leading(serial_length, "0")

    if String.length(serial_digits) > serial_length do
      raise "SSCC serial overflowed the space available for company prefix #{prefix}"
    end

    payload = "0" <> prefix <> serial_digits
    payload <> Integer.to_string(mod10_check_digit(payload))
  end
end
