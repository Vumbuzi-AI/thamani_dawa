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

  @doc "Lists an organization's sites with pagination."
  def list_sites_paginated(organization_id, page \\ 1) do
    from(s in Site, where: s.organization_id == ^organization_id)
    |> Repo.paginate(page: page)
  end

  @doc "Gets a single site scoped to an organization. Raises if not found."
  def get_site!(organization_id, id) do
    Repo.get_by!(Site, id: id, organization_id: organization_id)
  end

  @doc """
  Whether `gln` is already in use by an existing site. Lets the signup
  wizard flag this as soon as the GLN itself is verified against the GS1
  registry, instead of only discovering the `unique_constraint(:gln)`
  conflict after the user has filled out every remaining step.
  """
  @spec gln_taken?(String.t()) :: boolean()
  def gln_taken?(gln) when is_binary(gln) and gln != "" do
    Repo.exists?(from(s in Site, where: s.gln == ^gln))
  end

  def gln_taken?(_gln), do: false

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
  Whether an organization has more than one site — the §5 gate for showing
  the optional requisition/transfer layer at all.
  """
  def multi_site?(organization_id) do
    Repo.aggregate(from(s in Site, where: s.organization_id == ^organization_id), :count) > 1
  end

  @doc "Whether an organization has at least one site capable of lab work."
  def lab_enabled?(organization_id) do
    Repo.exists?(
      from s in Site,
        where: s.organization_id == ^organization_id,
        where: fragment("? @> ?", s.activities, ^["laboratory"])
    )
  end

  @doc """
  Convenience constructor for a basic pharmacy site, with placeholder PPB
  fields auto-filled since `Site.default_changeset/2` requires them for a
  pharmacy activity. The real signup flow (`Organizations.signup/3`) never
  calls this arity — it always supplies real, user-entered PPB details via
  the map-attrs clause below — so this exists for tests/fixtures that just
  need *a* working site and don't care about PPB verification specifically.
  """
  def create_default_site(organization_id, name)
      when is_integer(organization_id) and is_binary(name) do
    create_default_site(organization_id, %{
      name: name,
      activities: [:pharmacy],
      ppb_facility_name: name,
      license_number: "AUTO-#{System.unique_integer([:positive])}"
    })
  end

  def create_default_site(organization_id, attrs)
      when is_integer(organization_id) and is_map(attrs) do
    %Site{}
    |> Site.default_changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.audited_insert()
  end

  @doc "Creates a site under the given organization."
  def create_site(organization_id, attrs) when is_integer(organization_id) do
    %Site{}
    |> Site.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.audited_insert()
  end

  @doc "Updates a site."
  def update_site(%Site{} = site, attrs) do
    site
    |> Site.changeset(attrs)
    |> Repo.audited_update()
  end
end
