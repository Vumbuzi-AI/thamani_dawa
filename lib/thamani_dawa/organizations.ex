defmodule ThamaniDawa.Organizations do
  @moduledoc """
  The tenant boundary. Every other context scopes its queries by the
  `organization_id` returned from here.
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Grp.GlnVerificationWorker
  alias ThamaniDawa.Grp.PrefixVerificationWorker
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites

  @doc "Gets a single organization. Raises if not found."
  def get_organization!(id), do: Repo.get!(Organization, id)

  def change_organization_gs1_settings(%Organization{} = organization, attrs \\ %{}) do
    Organization.gs1_settings_changeset(organization, attrs)
  end

  def change_organization_details(%Organization{} = organization, attrs \\ %{}) do
    Organization.details_changeset(organization, attrs)
  end

  def change_organization_settings(%Organization{} = organization, attrs \\ %{}) do
    Organization.settings_changeset(organization, attrs)
  end

  def update_organization_settings(%Organization{} = organization, attrs) do
    changeset = Organization.settings_changeset(organization, attrs)
    gln_changed? = Ecto.Changeset.get_change(changeset, :gln) not in [nil, ""]

    with {:ok, updated} <- Repo.update(changeset) do
      if gln_changed? do
        Oban.insert(GlnVerificationWorker.new(%{record: "organization", id: updated.id}))
      end

      {:ok, updated}
    end
  end

  def update_organization_details(%Organization{} = organization, attrs) do
    organization
    |> Organization.details_changeset(attrs)
    |> Repo.update()
  end

  @doc "Marks the organization's GS1 company prefix verification status directly (skips Oban)."
  def mark_prefix_verification_status(%Organization{} = organization, status)
      when status in [:verified, :failed] do
    organization
    |> Ecto.Changeset.change(gs1_prefix_verification_status: status)
    |> Repo.update()
  end

  @doc "Marks the organization's GLN as verified directly (skips Oban)."
  def mark_gln_verified(%Organization{} = organization) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    organization
    |> Ecto.Changeset.change(gln_verified_at: now, gln_verification_source: "GS1 GRP")
    |> Repo.update()
  end

  def update_organization_gs1_settings(%Organization{} = organization, attrs) do
    changeset = Organization.gs1_settings_changeset(organization, attrs)
    gln_changed? = Ecto.Changeset.get_change(changeset, :gln) not in [nil, ""]

    with {:ok, updated} <- Repo.update(changeset) do
      if gln_changed? do
        Oban.insert(GlnVerificationWorker.new(%{record: "organization", id: updated.id}))
      end

      {:ok, updated}
    end
  end

  @doc false
  def create_organization(attrs) do
    %Organization{}
    |> Organization.changeset(attrs)
    |> Repo.insert()
  end

  defp create_signup_organization(attrs) do
    %Organization{}
    |> Organization.signup_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Signs up a brand-new organization by creating the organization, selected
  first site, and first admin in one transaction. The site's GLN (there is
  only ever one site at this point) is also copied onto the organization
  itself, since org-level events with no site attached — such as org-portal
  receiving — fall back to the organization's own GLN. Verification of the
  entered GS1 company prefix and GLN(s) is enqueued as background jobs and
  never blocks or fails the account itself.
  """
  def signup(org_attrs, site_attrs, admin_attrs) do
    Repo.transaction(fn ->
      with {:ok, organization} <- create_signup_organization(org_attrs),
           {:ok, site} <- Sites.create_default_site(organization.id, site_attrs),
           {:ok, organization} <- copy_site_gln(organization, site),
           {:ok, user} <- Accounts.register_user(organization.id, admin_attrs) do
        enqueue_verifications(organization, site)

        %{organization: organization, site: site, user: user}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp copy_site_gln(organization, %{gln: gln}) when gln not in [nil, ""] do
    organization
    |> Ecto.Changeset.change(gln: gln)
    |> Repo.update()
  end

  defp copy_site_gln(organization, _site), do: {:ok, organization}

  defp enqueue_verifications(organization, site) do
    if organization.gs1_company_prefix not in [nil, ""] do
      Oban.insert(PrefixVerificationWorker.new(%{organization_id: organization.id}))
    end

    if site.gln not in [nil, ""] do
      Oban.insert(GlnVerificationWorker.new(%{record: "site", id: site.id}))
    end

    if organization.gln not in [nil, ""] do
      Oban.insert(GlnVerificationWorker.new(%{record: "organization", id: organization.id}))
    end
  end

  @doc "Backward-compatible signup with a first site derived from operating models."
  def signup(org_attrs, admin_attrs) do
    signup(org_attrs, default_site_attrs(org_attrs), admin_attrs)
  end

  defp default_site_attrs(org_attrs) do
    models = Map.get(org_attrs, "operating_models", Map.get(org_attrs, :operating_models, []))

    %{
      "name" => Map.get(org_attrs, "name", Map.get(org_attrs, :name)),
      "activities" => default_site_activities(models)
    }
  end

  defp default_site_activities(models) do
    activities =
      models
      |> Enum.map(&to_string/1)
      |> Enum.flat_map(fn
        "pharmacy" -> ["pharmacy"]
        "laboratory" -> ["laboratory"]
        "distributor" -> ["distribution"]
        _ -> []
      end)

    if activities == [], do: ["pharmacy"], else: activities
  end
end
