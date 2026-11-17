defmodule ThamaniDawa.Distributor.GlnLookup do
  @moduledoc """
  GLN resolution for shipments and receipts. An origin (where a shipment
  ships from, or — for receiving — the sender) is always one of the
  organization's own active sites. A party on the other end (a shipment's
  destination, or a receipt's origin) can be anyone: another organization's
  site on this platform, or any GS1-registered company at all — resolved
  live, never stored locally, mirroring the GS1 reference implementation's
  "local directory first, GS1 registry fallback second" pattern.
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.Grp
  alias ThamaniDawa.Grp.Licence
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites.Site

  @type resolved :: %{
          gln: String.t(),
          company: String.t(),
          address: String.t() | nil,
          po_box: String.t() | nil,
          site_id: pos_integer() | nil
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

  @doc "Resolves an origin GLN to one of the organization's own active sites."
  @spec resolve_origin(pos_integer(), String.t() | nil) ::
          {:ok, resolved()} | {:error, :not_found}
  def resolve_origin(organization_id, gln) when is_binary(gln) do
    case Repo.get_by(Site, organization_id: organization_id, gln: gln, is_active: true) do
      nil ->
        {:error, :not_found}

      site ->
        {:ok,
         %{gln: gln, company: site.name, address: site.address, po_box: nil, site_id: site.id}}
    end
  end

  def resolve_origin(_organization_id, _gln), do: {:error, :not_found}

  @doc """
  Resolves a GLN to whichever party it belongs to — this platform's own
  active sites first (any organization, so an inter-org delivery between
  two thamani_dawa tenants resolves locally), then the live GS1 registry
  for any other GS1-registered company. Used for a shipment's destination
  and a goods receipt's origin alike.
  """
  @spec resolve_party(String.t() | nil) :: {:ok, resolved()} | {:error, :not_found}
  def resolve_party(gln) when is_binary(gln) do
    case Repo.get_by(Site, gln: gln, is_active: true) do
      %Site{} = site ->
        {:ok,
         %{gln: gln, company: site.name, address: site.address, po_box: nil, site_id: site.id}}

      nil ->
        resolve_via_registry(gln)
    end
  end

  def resolve_party(_gln), do: {:error, :not_found}

  defp resolve_via_registry(gln) do
    case Grp.verify_gln(gln) do
      {:ok, :verified, licence} ->
        {:ok,
         %{
           gln: gln,
           company: Licence.name(licence),
           address: Licence.address(licence),
           po_box: nil,
           site_id: nil
         }}

      _other ->
        {:error, :not_found}
    end
  end

  defp like_pattern(term) do
    escaped = Regex.replace(~r/[\\%_]/, String.trim(term || ""), fn char -> "\\" <> char end)
    "%" <> escaped <> "%"
  end
end
