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
  alias ThamaniDawa.Kmlttb.VerificationWorker, as: KmlttbVerificationWorker
  alias ThamaniDawa.Ppb.VerificationWorker, as: PpbVerificationWorker
  alias ThamaniDawa.Products
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site

  @doc "Gets a single organization. Raises if not found."
  def get_organization!(id), do: Repo.get!(Organization, id)

  @doc """
  Whether `name` collides with an existing organization's name (ignoring
  case/accents/punctuation, the same normalization the DB-level `name_key`
  uniqueness constraint enforces at insert time). Lets the signup wizard
  flag a collision as soon as the GS1 prefix resolves a name, instead of
  only discovering it after the user has filled out every remaining step.
  """
  @spec organization_name_taken?(String.t()) :: boolean()
  def organization_name_taken?(name) when is_binary(name) and name != "" do
    key = Organization.name_key(name)
    Repo.exists?(from(o in Organization, where: o.name_key == ^key))
  end

  def organization_name_taken?(_name), do: false

  @doc """
  Builds the post-signup "getting started" checklist for `organization`.
  The primary location is created during signup and is intentionally not
  repeated here. Shared by the inline checklist card on
  `OrgDashboardLive` and the full-screen `OnboardingLive` flow, so both read
  item completion from the same place rather than duplicating the done?
  logic.

  Order: Branches/sites, Team, and Products — the last item only for
  organizations that actually dispense or distribute stock.
  """
  def onboarding_checklist(%Organization{} = organization, _primary_site) do
    [
      %{
        key: :add_branch,
        label: "Set up your locations",
        description: "Add the branches your team will work from before inviting them.",
        cta: "Add a branch",
        done?: Sites.multi_site?(organization.id),
        path: "/org/sites/new"
      },
      %{
        key: :invite_team,
        label: "Build your team",
        description: "Invite staff and assign the branches they can work from.",
        cta: "Invite a teammate",
        done?: length(Accounts.list_users(organization.id)) > 1,
        path: "/org/team/new"
      }
    ]
    |> maybe_add_checklist_item(organization, :first_product, [:pharmacy, :distributor],
      label: "Add your products",
      description: "Build your catalogue so stock can be received and dispensed.",
      cta: "Add a product",
      done?: &(Products.list_products(&1) != []),
      path: "/org/products/new"
    )
  end

  @doc """
  `{completed, total}` counts for `onboarding_checklist/2`, used by every
  onboarding-step page (`OnboardingLive`, and each embedded step's own
  progress bar via `.onboarding_task_shell`/`TeamLive.Index`) to render a
  consistent progress bar without each one recomputing the checklist by
  hand.
  """
  @spec onboarding_progress(Organization.t()) :: {non_neg_integer(), non_neg_integer()}
  def onboarding_progress(%Organization{} = organization) do
    items = onboarding_checklist(organization, nil)
    {Enum.count(items, & &1.done?), length(items)}
  end

  defp maybe_add_checklist_item(items, organization, key, applicable_models, opts) do
    if Enum.any?(organization.operating_models, &(&1 in applicable_models)) do
      done_check = Keyword.fetch!(opts, :done?)

      items ++
        [
          %{
            key: key,
            label: Keyword.fetch!(opts, :label),
            description: Keyword.fetch!(opts, :description),
            cta: Keyword.fetch!(opts, :cta),
            done?: done_check.(organization.id),
            path: Keyword.fetch!(opts, :path)
          }
        ]
    else
      items
    end
  end

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
    |> Ecto.Changeset.change(gln_verified_at: now)
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

  @doc "Whether this org's EPCIS events send automatically as they're enqueued, or wait for a manual trigger."
  def update_epcis_submission_mode(%Organization{} = organization, mode)
      when mode in ["automatic", "manual", :automatic, :manual] do
    organization
    |> Organization.epcis_submission_mode_changeset(%{epcis_submission_mode: mode})
    |> Repo.update()
  end

  @doc """
  Sets (or, given `""`/`nil`, clears) this org's own PPB API key for one
  tier. Clearing falls back to the platform-wide key configured on
  `ThamaniDawa.Epcis.Client` for that tier.
  """
  def set_epcis_api_key(%Organization{} = organization, tier, key)
      when tier in ["distributor", "facility"] do
    organization
    |> Organization.epcis_api_key_changeset(tier, key)
    |> Repo.update()
  end

  @doc "Clears an org's own PPB API key for one tier, falling back to the platform-wide key."
  def clear_epcis_api_key(%Organization{} = organization, tier) do
    set_epcis_api_key(organization, tier, nil)
  end

  @doc """
  The organization's GS1 member API token, or `nil` when none is saved.
  Callers pass this when creating an SSCC or fetching case contents; `nil`
  means use the platform token.
  """
  def gs1_api_key(%Organization{gs1_api_key: key}) when is_binary(key) and key != "", do: key
  def gs1_api_key(%Organization{}), do: nil

  def gs1_api_key(organization_id) when is_integer(organization_id) do
    case Repo.get(Organization, organization_id) do
      %Organization{} = organization -> gs1_api_key(organization)
      nil -> nil
    end
  end

  def gs1_api_key(_organization), do: nil

  @doc """
  Sets (or, given `""`/`nil`, clears) this organization's GS1 member API token.
  Clearing falls back to the platform token for SSCC creation and fetching.
  """
  def set_gs1_api_key(%Organization{} = organization, key) do
    organization
    |> Organization.gs1_api_key_changeset(key)
    |> Repo.update()
  end

  @doc "Dismisses the dashboard's 'Getting started' checklist for this organization."
  def dismiss_onboarding_checklist(%Organization{} = organization) do
    organization
    |> Organization.dismiss_onboarding_checklist_changeset()
    |> Repo.update()
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
           {:ok, user} <-
             Accounts.register_user(organization.id, admin_attrs, organization.operating_models) do
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

    if Site.ppb_ftype(site) && site.ppb_facility_name not in [nil, ""] &&
         site.license_number not in [nil, ""] do
      Oban.insert(PpbVerificationWorker.new(%{site_id: site.id}))
    end

    if Site.kmlttb_required?(site) && site.kmlttb_facility_name not in [nil, ""] &&
         site.kmlttb_license_number not in [nil, ""] do
      Oban.insert(KmlttbVerificationWorker.new(%{site_id: site.id}))
    end
  end

  @doc "Backward-compatible signup with a first site derived from operating models."
  def signup(org_attrs, admin_attrs) do
    signup(org_attrs, default_site_attrs(org_attrs), admin_attrs)
  end

  # Site-level PPB/KMLTTB licensing is required whenever the resulting
  # activities call for it (see `Site.ppb_ftype/1`/`Site.kmlttb_required?/1`),
  # so this backward-compatible path forwards the same fields a caller
  # would otherwise already be passing at the organization level (PPB) or
  # must now pass explicitly for lab activities (KMLTTB) — there's no
  # org-level KMLTTB field to fall back on, since that's always been a
  # site-only concern.
  defp default_site_attrs(org_attrs) do
    models = Map.get(org_attrs, "operating_models", Map.get(org_attrs, :operating_models, []))

    %{
      "name" => get_attr(org_attrs, :name),
      "activities" => default_site_activities(models),
      "ppb_facility_name" => get_attr(org_attrs, :ppb_facility_name),
      "license_number" => get_attr(org_attrs, :license_number),
      "kmlttb_facility_name" => get_attr(org_attrs, :kmlttb_facility_name),
      "kmlttb_license_number" => get_attr(org_attrs, :kmlttb_license_number)
    }
  end

  defp get_attr(attrs, key), do: Map.get(attrs, Atom.to_string(key), Map.get(attrs, key))

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
