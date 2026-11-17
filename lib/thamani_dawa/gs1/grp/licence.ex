defmodule ThamaniDawa.Grp.Licence do
  @moduledoc """
  Pulls a display name and postal-style address out of a GS1 GRP licence
  map (`ThamaniDawa.Grp.verify_prefix/1`/`verify_gln/1`'s successful return
  value). Shared by every place that autofills a name/address field from a
  verified GLN or company prefix (the signup wizard's regulatory-details and
  main-location steps, `SiteLive.Index`'s "Add a site" form), so the parsing
  rules only live in one place.
  """

  @doc "Extracts a display name from a GRP licence map."
  def name(licence) when is_map(licence) do
    Enum.find_value(
      ["licenseeName", "partyName", "organizationName", "companyName", "name"],
      fn key ->
        case Map.get(licence, key) do
          value when is_binary(value) and value != "" -> value
          _ -> nil
        end
      end
    )
  end

  def name(_licence), do: nil

  # Builds a full postal-style address from the GRP licence's `address`
  # object (streetAddress, region, locality, PO box, postal code, country)
  # instead of just the locality — GS1's sandbox data uses the literal
  # string "none" as a placeholder for fields with no value, so that's
  # filtered out alongside genuinely blank ones. `addressSuburb` and
  # `crossStreet` are deliberately skipped — sandbox data has shown them
  # holding junk (e.g. a country name) rather than real address components.
  @doc "Extracts a joined postal address from a GRP licence map."
  def address(licence) when is_map(licence) do
    address = Map.get(licence, "address", %{})

    [
      field(address, "streetAddress"),
      field(address, "streetAddressLine2"),
      field(address, "addressRegion"),
      field(address, "addressLocality"),
      po_box_line(address),
      country_name(Map.get(address, "countryCode"))
    ]
    |> Enum.reject(&blank_or_placeholder?/1)
    |> case do
      [] -> nil
      lines -> Enum.join(lines, ", ")
    end
  end

  def address(_licence), do: nil

  defp field(address, key) do
    case Map.get(address, key) do
      %{"value" => value} -> value
      value when is_binary(value) -> value
      _ -> nil
    end
  end

  defp po_box_line(address) do
    box = Map.get(address, "postOfficeBoxNumber")
    code = Map.get(address, "postalCode")

    case {blank?(box), blank?(code)} do
      {true, true} -> nil
      {false, true} -> "P.O. Box #{box}"
      {true, false} -> code
      {false, false} -> "P.O. Box #{box}-#{code}"
    end
  end

  defp country_name("KE"), do: "Kenya"
  defp country_name(code) when is_binary(code) and code != "", do: code
  defp country_name(_code), do: nil

  defp blank_or_placeholder?(value) do
    blank?(value) or (is_binary(value) and String.downcase(String.trim(value)) == "none")
  end

  defp blank?(nil), do: true
  defp blank?(value), do: value |> to_string() |> String.trim() == ""
end
