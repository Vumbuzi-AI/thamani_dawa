defmodule ThamaniDawa.Gln do
  @moduledoc """
  Auto-generates GS1 Global Location Numbers for `sites.gln` and
  `suppliers.gln`. A GLN is a 13-digit code: the organization's GS1 company
  prefix, a random extension filling out the remaining digits, and a GS1
  check digit — so it's never entered or shown as an editable field in the
  UI.
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawa.Suppliers.Supplier

  @gln_length 12
  @max_attempts 10

  @doc """
  Generates a GLN unique across sites and suppliers, retrying on the rare
  collision with an already-assigned GLN.
  """
  def generate! do
    Enum.find_value(1..@max_attempts, fn _ -> generate_candidate() end) ||
      raise "could not generate a unique GLN after #{@max_attempts} attempts"
  end

  defp generate_candidate do
    gln = ExGtin.generate!(base_code())
    if unique?(gln), do: gln
  end

  defp base_code do
    prefix = company_prefix()
    extension_length = @gln_length - String.length(prefix)
    prefix <> random_digits(extension_length)
  end

  defp random_digits(length) do
    Enum.map_join(1..length, fn _ -> Integer.to_string(:rand.uniform(10) - 1) end)
  end

  defp company_prefix do
    config = Application.get_env(:thamani_dawa, __MODULE__, [])
    Keyword.fetch!(config, :company_prefix)
  end

  defp unique?(gln) do
    not Repo.exists?(from s in Site, where: s.gln == ^gln) and
      not Repo.exists?(from s in Supplier, where: s.gln == ^gln)
  end
end
