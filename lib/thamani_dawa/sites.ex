defmodule ThamaniDawa.Sites do
  @moduledoc """
  Pharmacy/lab branches and warehouses. Every organization gets one default
  site created in the same transaction as its signup — see
  `ThamaniDawa.Organizations.signup/2` — and only gains the
  requisition/transfer layer once it has more than one (§5 of project.md).
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites.Site

  @doc "Lists an organization's sites."
  def list_sites(organization_id) do
    Repo.all(from s in Site, where: s.organization_id == ^organization_id)
  end

  @doc "Gets a single site scoped to an organization. Raises if not found."
  def get_site!(organization_id, id) do
    Repo.get_by!(Site, id: id, organization_id: organization_id)
  end

  @doc """
  Resolves a scanned GLN (GS1 AI `414`) to a site under the given
  organization (§9 "GLN site lookup"). Returns `{:error, :not_found}` when
  no site with that GLN exists in this organization.
  """
  def get_site_by_gln(organization_id, gln) do
    case Repo.get_by(Site, organization_id: organization_id, gln: gln) do
      nil -> {:error, :not_found}
      site -> {:ok, site}
    end
  end

  @doc """
  Creates the default site for a brand-new organization (§2.3.1) — a
  `pharmacy`-type site named after the organization, so a single-pharmacy
  owner never has to think about "sites" as a concept.
  """
  def create_default_site(organization_id, name) when is_integer(organization_id) do
    %Site{}
    |> Site.default_changeset(%{name: name, site_type: :pharmacy})
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.insert()
  end

  @doc "Creates a site under the given organization."
  def create_site(organization_id, attrs) when is_integer(organization_id) do
    %Site{}
    |> Site.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.insert()
  end

  @doc "Updates a site."
  def update_site(%Site{} = site, attrs) do
    site
    |> Site.changeset(attrs)
    |> Repo.update()
  end
end
