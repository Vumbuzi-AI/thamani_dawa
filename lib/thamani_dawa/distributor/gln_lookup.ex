defmodule ThamaniDawa.Distributor.GlnLookup do
  @moduledoc """
  GLN resolution for shipments. Origins are the organization's own sites
  (warehouses and other premises); destinations are its customers. Both
  carry auto-generated GLNs (`ThamaniDawa.Gln`).
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.DistributorCustomers.Customer
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites.Site

  @type resolved :: %{
          gln: String.t(),
          company: String.t(),
          address: String.t() | nil,
          po_box: String.t() | nil,
          record: struct()
        }

  @doc "Searches the organization's own active sites by name or GLN."
  def search_origin(organization_id, term, limit \\ 10) do
    pattern = like_pattern(term)

    Repo.all(
      from s in Site,
        where: s.organization_id == ^organization_id and s.is_active,
        where: not is_nil(s.gln),
        where: ilike(s.name, ^pattern) or ilike(s.gln, ^pattern),
        order_by: [
          desc: fragment("? @> ?", s.activities, ^["distribution"]),
          asc: s.name
        ],
        limit: ^limit
    )
  end

  @doc "Searches the organization's active customers by name or GLN."
  def search_destination(organization_id, term, limit \\ 10) do
    pattern = like_pattern(term)

    Repo.all(
      from c in Customer,
        where: c.organization_id == ^organization_id and c.is_active,
        where: ilike(c.name, ^pattern) or ilike(c.gln, ^pattern),
        order_by: [asc: c.name],
        limit: ^limit
    )
  end

  @doc "Resolves an origin GLN to one of the organization's own active sites."
  @spec resolve_origin(pos_integer(), String.t() | nil) ::
          {:ok, resolved()} | {:error, :not_found}
  def resolve_origin(organization_id, gln) when is_binary(gln) do
    case Repo.get_by(Site, organization_id: organization_id, gln: gln, is_active: true) do
      nil ->
        {:error, :not_found}

      site ->
        {:ok, %{gln: gln, company: site.name, address: site.address, po_box: nil, record: site}}
    end
  end

  def resolve_origin(_organization_id, _gln), do: {:error, :not_found}

  @doc "Resolves a destination GLN to one of the organization's active customers."
  @spec resolve_destination(pos_integer(), String.t() | nil) ::
          {:ok, resolved()} | {:error, :not_found}
  def resolve_destination(organization_id, gln) when is_binary(gln) do
    case Repo.get_by(Customer, organization_id: organization_id, gln: gln, is_active: true) do
      nil ->
        {:error, :not_found}

      customer ->
        {:ok,
         %{
           gln: gln,
           company: customer.name,
           address: customer.address,
           po_box: customer.po_box,
           record: customer
         }}
    end
  end

  def resolve_destination(_organization_id, _gln), do: {:error, :not_found}

  defp like_pattern(term) do
    escaped = Regex.replace(~r/[\\%_]/, String.trim(term || ""), fn char -> "\\" <> char end)
    "%" <> escaped <> "%"
  end
end
