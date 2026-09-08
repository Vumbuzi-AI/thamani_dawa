defmodule ThamaniDawa.Organizations do
  @moduledoc """
  The tenant boundary. Every other context scopes its queries by the
  `organization_id` returned from here.
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.{Accounts, Sites}
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Repo

  @doc "Gets a single organization. Raises if not found."
  def get_organization!(id), do: Repo.get!(Organization, id)

  @doc "The organization's kind (`:healthcare` or `:distributor`, §1 of serialisation.md)."
  def get_kind!(organization_id), do: get_organization!(organization_id).kind

  @doc "Whether the organization is a distributor/manufacturer tenant (serialisation-only)."
  def distributor?(organization_id), do: get_kind!(organization_id) == :distributor

  @doc "Whether the organization is a healthcare (pharmacy/lab) tenant."
  def healthcare?(organization_id), do: get_kind!(organization_id) == :healthcare

  @doc false
  def create_organization(attrs) do
    %Organization{}
    |> Organization.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Signs up a brand-new organization (§2.3.1): creates the `organizations`
  row, a default `sites` row, and the org's first admin `users` row, all in
  one transaction. Rolls back everything if any step fails.

  A `:distributor` organization (serialisation.md §1) gets a `:warehouse`
  default site instead of a `:pharmacy` one — it has no dispensing or lab
  work, only shipments to serialise.
  """
  def signup(org_attrs, admin_attrs) do
    Repo.transaction(fn ->
      with {:ok, organization} <- create_organization(org_attrs),
           {:ok, site} <-
             Sites.create_default_site(
               organization.id,
               organization.name,
               default_site_type(organization.kind)
             ),
           {:ok, user} <- Accounts.register_user(organization.id, admin_attrs) do
        %{organization: organization, site: site, user: user}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp default_site_type(:distributor), do: :warehouse
  defp default_site_type(:healthcare), do: :pharmacy
end
