defmodule ThamaniDawa.Distributor.VatStatus do
  @moduledoc """
  Whether VAT applies to an organization's serialisation charges. Driven by
  `organizations.vat_registered` (default `true`, placeholder pending
  confirmation of the VAT rule).
  """

  alias ThamaniDawa.Organizations.Organization

  def applicable?(%Organization{vat_registered: false}), do: false
  def applicable?(_organization), do: true
end
