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

  @doc false
  def create_organization(attrs) do
    %Organization{}
    |> Organization.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Signs up a brand-new organization by creating the organization, selected
  first site, and first admin in one transaction.
  """
  def signup(org_attrs, site_attrs, admin_attrs) do
    Repo.transaction(fn ->
      with {:ok, organization} <- create_organization(org_attrs),
           {:ok, site} <- Sites.create_default_site(organization.id, site_attrs),
           {:ok, user} <- Accounts.register_user(organization.id, admin_attrs) do
        %{organization: organization, site: site, user: user}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc "Backward-compatible signup with a first site derived from operating models."
  def signup(org_attrs, admin_attrs) do
    signup(org_attrs, default_site_attrs(org_attrs), admin_attrs)
  end

  defp default_site_attrs(org_attrs) do
    models = Map.get(org_attrs, "operating_models", Map.get(org_attrs, :operating_models, []))

    %{
      "name" => Map.get(org_attrs, "name", Map.get(org_attrs, :name)),
      "site_type" => default_site_type(models)
    }
  end

  defp default_site_type(models) do
    normalized = Enum.map(models, &to_string/1)

    cond do
      "distributor" in normalized -> "warehouse"
      "pharmacy" in normalized and "laboratory" in normalized -> "pharmacy_lab"
      "laboratory" in normalized -> "lab"
      true -> "pharmacy"
    end
  end
end
