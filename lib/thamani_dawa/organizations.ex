defmodule ThamaniDawa.Organizations do
  @moduledoc """
  The tenant boundary. Every other context scopes its queries by the
  `organization_id` returned from here.
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.{Accounts, Sites}

  @doc "Gets a single organization. Raises if not found."
  def get_organization!(id), do: Repo.get!(Organization, id)

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
  """
  def signup(org_attrs, admin_attrs) do
    Repo.transaction(fn ->
      with {:ok, organization} <- create_organization(org_attrs),
           {:ok, site} <- Sites.create_default_site(organization.id, organization.name),
           {:ok, user} <- Accounts.register_user(organization.id, admin_attrs) do
        %{organization: organization, site: site, user: user}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end
end
