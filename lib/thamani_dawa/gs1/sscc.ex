defmodule ThamaniDawa.GS1.Sscc do
  @moduledoc """
  SSCC-18 (Serial Shipping Container Code) allocation for distributor
  shippers (cases). One SSCC is issued per shipper when its shipment is
  approved.

  Format: extension digit (1) + GS1 Company Prefix (6–10 digits) +
          serial reference (fills remaining to 17 digits) + Mod10 check digit = 18 digits total.

  Serial references are claimed with a single atomic `UPDATE ... SET
  next_sscc_serial = next_sscc_serial + n`, so two concurrent approvals never
  receive overlapping ranges.
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Repo

  @doc """
  Returns the organization's GS1 Company Prefix, or
  `{:error, :missing_gs1_company_prefix}` when it hasn't been configured.
  """
  @spec prefix_for_organization(pos_integer()) ::
          {:ok, String.t()} | {:error, :missing_gs1_company_prefix}
  def prefix_for_organization(organization_id) when is_integer(organization_id) do
    case Repo.get!(Organization, organization_id).gs1_company_prefix do
      prefix when prefix in [nil, ""] -> {:error, :missing_gs1_company_prefix}
      prefix -> {:ok, prefix}
    end
  end

  @doc "Generates a single SSCC-18 for `organization_id`."
  @spec generate(pos_integer()) :: {:ok, String.t()} | {:error, :missing_gs1_company_prefix}
  def generate(organization_id) when is_integer(organization_id) do
    with {:ok, [sscc]} <- allocate(organization_id, 1), do: {:ok, sscc}
  end

  @doc """
  Allocates `count` consecutive SSCC-18s for `organization_id` in one atomic
  serial claim. Must be called inside the caller's transaction when the
  SSCCs are persisted alongside other rows.
  """
  @spec allocate(pos_integer(), pos_integer()) ::
          {:ok, [String.t()]} | {:error, :missing_gs1_company_prefix}
  def allocate(organization_id, count)
      when is_integer(organization_id) and is_integer(count) and count > 0 do
    with {:ok, prefix} <- prefix_for_organization(organization_id) do
      {1, [last_serial]} =
        Repo.update_all(
          from(o in Organization, where: o.id == ^organization_id, select: o.next_sscc_serial),
          inc: [next_sscc_serial: count]
        )

      first_serial = last_serial - count + 1
      {:ok, Enum.map(first_serial..last_serial, &build_sscc(prefix, &1))}
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

  defp build_sscc(prefix, serial) do
    serial_length = 16 - String.length(prefix)
    serial_digits = serial |> Integer.to_string() |> String.pad_leading(serial_length, "0")

    if String.length(serial_digits) > serial_length do
      raise "SSCC serial overflowed the space available for company prefix #{prefix}"
    end

    payload = "0" <> prefix <> serial_digits
    payload <> Integer.to_string(mod10_check_digit(payload))
  end
end
