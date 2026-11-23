defmodule ThamaniDawa.Organizations do
  @moduledoc """
  The tenant boundary. Every other context scopes its queries by the
  `organization_id` returned from here.
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Accounts
  alias ThamaniDawa.GS1.MemberApi
  alias ThamaniDawa.Grp.GlnVerificationWorker
  alias ThamaniDawa.Grp.PrefixVerificationWorker
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Organizations.OrganizationGs1Prefix
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
    |> maybe_add_checklist_item(
      organization,
      :connect_keys,
      [:pharmacy, :laboratory, :distributor, :manufacturer],
      label: "Connect your tracing keys",
      description: "Add your EPCIS keys so PPB reporting works.",
      cta: "Add API keys",
      done?: fn _ -> keys_ready?(organization) end,
      path: "/org/api-keys?return_to=onboarding"
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

  @doc "Marks a GS1 company prefix's verification status directly (skips Oban)."
  def mark_prefix_verification_status(%OrganizationGs1Prefix{} = prefix, status)
      when status in [:verified, :failed] do
    now = if status == :verified, do: DateTime.utc_now(:second)

    prefix
    |> Ecto.Changeset.change(verification_status: status, verified_at: now)
    |> Repo.update()
  end

  @doc "Lists an organization's GS1 company prefixes, primary first."
  def list_gs1_prefixes(organization_id) do
    Repo.all(
      from p in OrganizationGs1Prefix,
        where: p.organization_id == ^organization_id,
        order_by: [desc: p.is_primary, asc: p.inserted_at]
    )
  end

  @doc "The organization's primary GS1 company prefix record, or `nil` if it has none."
  def primary_gs1_prefix(organization_id) do
    Repo.one(
      from p in OrganizationGs1Prefix,
        where: p.organization_id == ^organization_id and p.is_primary
    )
  end

  def change_gs1_prefix(%OrganizationGs1Prefix{} = prefix \\ %OrganizationGs1Prefix{}, attrs) do
    OrganizationGs1Prefix.changeset(prefix, attrs)
  end

  @doc """
  Adds a new GS1 company prefix to an organization and enqueues its
  verification against the GS1 registry. The first prefix an organization
  adds automatically becomes its primary one (used for building
  GTINs/SSCCs); later prefixes are added as secondary unless the caller
  explicitly promotes one with `set_primary_gs1_prefix/1`.
  """
  def add_gs1_prefix(%Organization{} = organization, attrs) do
    is_primary = is_nil(primary_gs1_prefix(organization.id))

    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("organization_id", organization.id)
      |> Map.put_new("is_primary", is_primary)

    with {:ok, prefix} <-
           %OrganizationGs1Prefix{} |> OrganizationGs1Prefix.changeset(attrs) |> Repo.insert() do
      Oban.insert(PrefixVerificationWorker.new(%{organization_gs1_prefix_id: prefix.id}))
      {:ok, prefix}
    end
  end

  @doc """
  Promotes `prefix` to be the organization's primary GS1 company prefix
  (the one used to build GTINs/SSCCs), demoting whichever prefix held that
  role before.
  """
  def set_primary_gs1_prefix(%OrganizationGs1Prefix{} = prefix) do
    Repo.transaction(fn ->
      from(p in OrganizationGs1Prefix,
        where: p.organization_id == ^prefix.organization_id and p.is_primary
      )
      |> Repo.update_all(set: [is_primary: false])

      prefix
      |> Ecto.Changeset.change(is_primary: true)
      |> Repo.update!()
    end)
  end

  @doc "Removes a GS1 company prefix from an organization."
  def delete_gs1_prefix(%OrganizationGs1Prefix{} = prefix), do: Repo.delete(prefix)

  @doc """
  Lists the GLNs registered to the organization's GS1 member account, as
  `{label, gln}` pairs ready for a combobox. Returns `[]` when the
  organization has no GS1 API key on file or the member API can't be
  reached — callers fall back to a free-text GLN field in that case.
  """
  def list_member_glns(%Organization{} = organization) do
    case gs1_api_key(organization) do
      nil ->
        []

      api_key ->
        case MemberApi.list_glns(api_token: api_key) do
          {:ok, glns} -> Enum.map(glns, &member_gln_option/1)
          {:error, _reason} -> []
        end
    end
  end

  def list_member_glns(organization_id) when is_integer(organization_id) do
    organization_id |> get_organization!() |> list_member_glns()
  end

  defp member_gln_option(row) do
    gln = Map.get(row, "gln")
    label = member_gln_description(row)
    {"#{label} — #{gln}", gln}
  end

  defp member_gln_description(row) do
    Enum.find_value(["description", "location", "address"], "", fn key ->
      value = Map.get(row, key, "")
      if blank?(value), do: nil, else: value
    end)
  end

  defp blank?(value), do: value in [nil, ""]

  @doc "Marks the organization's GLN as verified directly (skips Oban)."
  def mark_gln_verified(%Organization{} = organization) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    organization
    |> Ecto.Changeset.change(gln_verified_at: now)
    |> Repo.update()
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
  tier. There is no platform-wide fallback: an org with no key for a tier
  gets its EPCIS submissions blocked until one is added.
  """
  def set_epcis_api_key(%Organization{} = organization, tier, key)
      when tier in ["distributor", "facility", "manufacturer"] do
    organization
    |> Organization.epcis_api_key_changeset(tier, key)
    |> Repo.update()
  end

  @doc "Clears an org's own PPB API key for one tier. EPCIS submissions block until a new one is added."
  def clear_epcis_api_key(%Organization{} = organization, tier) do
    set_epcis_api_key(organization, tier, nil)
  end

  @doc """
  The organization's GS1 member API token, or `nil` when none is saved.
  Callers pass this when creating an SSCC or fetching case contents; `nil`
  means the call is refused with `{:error, :unconfigured}` — there is no
  platform-wide token to fall back to.
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
  receiving — fall back to the organization's own GLN. GS1 details fetched
  during signup (the member API key, company prefixes, and the chosen
  primary prefix) are persisted in the same transaction. Verification of
  the GLN(s) is enqueued as a background job and never blocks or fails the
  account itself.
  """
  def signup(org_attrs, site_attrs, admin_attrs, opts \\ []) do
    Repo.transaction(fn ->
      with {:ok, organization} <- create_signup_organization(org_attrs),
           {:ok, organization} <- persist_gs1_details(organization, Keyword.get(opts, :gs1)),
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

  defp persist_gs1_details(organization, nil), do: {:ok, organization}

  defp persist_gs1_details(organization, %{} = gs1) do
    api_key = Map.get(gs1, :api_key) || Map.get(gs1, "api_key")
    prefixes = Map.get(gs1, :prefixes) || Map.get(gs1, "prefixes") || []
    primary_prefix = Map.get(gs1, :primary_prefix) || Map.get(gs1, "primary_prefix")

    with {:ok, organization} <- maybe_set_gs1_api_key(organization, api_key),
         {:ok, added} <- add_gs1_prefixes(organization, prefixes) do
      promote_primary_prefix(organization, added, primary_prefix)
    end
  end

  defp maybe_set_gs1_api_key(organization, key) when key in [nil, ""], do: {:ok, organization}
  defp maybe_set_gs1_api_key(organization, key), do: set_gs1_api_key(organization, key)

  defp add_gs1_prefixes(organization, prefixes) do
    prefixes
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn prefix, {:ok, added} ->
      case add_gs1_prefix(organization, %{prefix: prefix}) do
        {:ok, record} -> {:cont, {:ok, [{prefix, record} | added]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, added} -> {:ok, Enum.reverse(added)}
      error -> error
    end
  end

  defp promote_primary_prefix(organization, _added, nil), do: {:ok, organization}

  defp promote_primary_prefix(organization, added, primary_prefix) do
    case Enum.find(added, fn {prefix, _record} -> prefix == to_string(primary_prefix) end) do
      nil ->
        {:ok, organization}

      {_prefix, %{is_primary: true}} ->
        {:ok, organization}

      {_prefix, record} ->
        case set_primary_gs1_prefix(record) do
          {:ok, _promoted} -> {:ok, organization}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  defp copy_site_gln(organization, %{gln: gln}) when gln not in [nil, ""] do
    organization
    |> Ecto.Changeset.change(gln: gln)
    |> Repo.update()
  end

  defp copy_site_gln(organization, _site), do: {:ok, organization}

  defp enqueue_verifications(organization, site) do
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

  defp keys_ready?(%Organization{} = organization) do
    Enum.all?(relevant_epcis_tiers(organization), &epcis_key_set?(organization, &1))
  end

  defp relevant_epcis_tiers(%Organization{operating_models: models}) do
    models = models || []

    [
      :distributor in models && "distributor",
      :manufacturer in models && "manufacturer",
      Enum.any?(models, &(&1 in [:pharmacy, :laboratory])) && "facility"
    ]
    |> Enum.filter(& &1)
  end

  defp epcis_key_set?(organization, "distributor"),
    do: present?(organization.epcis_distributor_api_key_last4)

  defp epcis_key_set?(organization, "manufacturer"),
    do: present?(organization.epcis_manufacturer_api_key_last4)

  defp epcis_key_set?(organization, "facility"),
    do: present?(organization.epcis_facility_api_key_last4)

  defp present?(value), do: value not in [nil, ""]
end
