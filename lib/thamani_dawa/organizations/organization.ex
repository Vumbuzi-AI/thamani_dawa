defmodule ThamaniDawa.Organizations.Organization do
  use Ecto.Schema
  import Ecto.Changeset

  @similar_name_message "An organization with a similar name already exists"
  @slug_index :organizations_slug_index
  @name_key_index :organizations_name_key_index
  @operating_models [:pharmacy, :laboratory, :distributor, :manufacturer]

  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :name_key, :string
    field :license_number, :string

    field :operating_models, {:array, Ecto.Enum},
      values: @operating_models,
      default: [:pharmacy]

    field :is_active, :boolean, default: true
    field :is_subscription_active, :boolean, default: false
    field :next_requisition_number, :integer, default: 0

    field :gln, :string
    field :gln_verified_at, :utc_datetime

    field :next_sscc_serial, :integer, default: 0
    field :next_goods_receipt_number, :integer, default: 0
    field :serialisation_type, :string
    field :vat_registered, :boolean, default: true
    field :next_serial_invoice_number, :integer, default: 0

    field :epcis_submission_mode, Ecto.Enum,
      values: [:automatic, :manual],
      default: :automatic

    field :epcis_distributor_api_key, ThamaniDawa.Encrypted.Binary
    field :epcis_distributor_api_key_last4, :string
    field :epcis_facility_api_key, ThamaniDawa.Encrypted.Binary
    field :epcis_facility_api_key_last4, :string
    field :epcis_manufacturer_api_key, ThamaniDawa.Encrypted.Binary
    field :epcis_manufacturer_api_key_last4, :string

    field :gs1_api_key, ThamaniDawa.Encrypted.Binary
    field :gs1_api_key_last4, :string

    field :onboarding_checklist_dismissed_at, :utc_datetime

    has_many :gs1_prefixes, ThamaniDawa.Organizations.OrganizationGs1Prefix
    has_many :sites, ThamaniDawa.Sites.Site
    has_many :users, ThamaniDawa.Accounts.User
    has_many :products, ThamaniDawa.Products.Product
    has_many :suppliers, ThamaniDawa.Suppliers.Supplier
    has_many :patients, ThamaniDawa.Patients.Patient
    has_many :patient_visits, ThamaniDawa.PatientVisits.PatientVisit
    has_many :batches, ThamaniDawa.Batches.Batch
    has_many :goods_receipts, ThamaniDawa.GoodsReceipts.GoodsReceipt
    has_many :prescriptions, ThamaniDawa.Prescriptions.Prescription
    has_many :lab_test_categories, ThamaniDawa.LabTests.LabTestCategory
    has_many :lab_tests, ThamaniDawa.LabTests.LabTest
    has_many :lab_orders, ThamaniDawa.LabOrders.LabOrder
    has_many :lab_order_results, ThamaniDawa.LabOrders.LabOrderResult
    has_many :lab_consumable_usages, ThamaniDawa.LabOrders.LabConsumableUsage
    has_many :payments, ThamaniDawa.Payments.Payment
    has_many :wallet_entries, ThamaniDawa.Payments.WalletEntry

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(organization, attrs) do
    organization
    |> base_changeset(attrs)
    |> validate_required([:license_number], message: "Please enter your license number")
  end

  defp base_changeset(organization, attrs) do
    organization
    |> cast(attrs, [:name, :slug, :license_number, :operating_models])
    |> trim_change(:name)
    |> trim_change(:license_number)
    |> validate_required([:name], message: "Please enter your organization name")
    |> validate_length(:operating_models,
      min: 1,
      message: "Select at least one operating model"
    )
    |> maybe_generate_slug()
    |> put_name_key()
    |> unique_constraint(:name, message: "An organization with this name already exists")
    |> unique_constraint(:name, name: @slug_index, message: @similar_name_message)
    |> unique_constraint(:name, name: @name_key_index, message: @similar_name_message)
  end

  @doc """
  Changeset for onboarding: organization name, license, and operating
  models. GS1 company prefixes are no longer collected at signup — an
  organization can have none, one, or several, added and verified later
  from the settings page.
  """
  def signup_changeset(organization, attrs) do
    base_changeset(organization, attrs)
  end

  @doc "The operating models an organization may enable during onboarding."
  def operating_models, do: @operating_models

  @doc "Whether the organization operates as a distributor."
  def distributor?(%__MODULE__{operating_models: models}) when is_list(models),
    do: :distributor in models

  def distributor?(_organization), do: false

  @doc "Whether the organization operates as a manufacturer."
  def manufacturer?(%__MODULE__{operating_models: models}) when is_list(models),
    do: :manufacturer in models

  def manufacturer?(_organization), do: false

  @doc "Changeset for the organization details editable from the settings page (licence, VAT status)."
  def details_changeset(organization, attrs) do
    organization
    |> cast(attrs, [:license_number, :vat_registered])
    |> trim_change(:license_number)
    |> validate_required([:license_number], message: "Please enter your license number")
  end

  @doc "Changeset for the organization settings editable from the settings page (licence, VAT status, GLN)."
  def settings_changeset(organization, attrs) do
    organization
    |> cast(attrs, [:license_number, :vat_registered, :gln])
    |> trim_change(:license_number)
    |> trim_change(:gln)
    |> validate_required([:license_number], message: "Please enter your license number")
    |> validate_format(:gln, ~r/^\d{13}$/, message: "must be a 13-digit GLN")
    |> validate_gln_check_digit()
  end

  @doc "Changeset for whether this org's EPCIS events send automatically or wait for a manual trigger."
  def epcis_submission_mode_changeset(organization, attrs) do
    organization
    |> cast(attrs, [:epcis_submission_mode])
    |> validate_required([:epcis_submission_mode])
  end

  @doc """
  Changeset for replacing an org's own PPB Track & Trace API key for one
  tier (`"distributor"` or `"facility"`). Also stamps the last 4 characters
  of the new key in a plaintext column so the settings page can display
  "ending in ••1234" without ever decrypting/re-rendering the secret.
  Blanking the key (empty string) clears both columns, which makes
  `Epcis.Client` fall back to the platform-wide key for that tier.
  """
  def epcis_api_key_changeset(organization, tier, key)
      when tier in ["distributor", "facility", "manufacturer"] do
    key = if is_binary(key), do: String.trim(key), else: key
    key_field = :"epcis_#{tier}_api_key"
    last4_field = :"epcis_#{tier}_api_key_last4"

    case key do
      "" ->
        change(organization, %{key_field => nil, last4_field => nil})

      nil ->
        change(organization, %{key_field => nil, last4_field => nil})

      _present ->
        change(organization, %{key_field => key, last4_field => String.slice(key, -4, 4)})
    end
  end

  @doc """
  Changeset for this organization's GS1 member API token. The token is the
  bearer credential for creating an SSCC and for fetching the serials inside
  a case. Blanking it clears both columns so those calls fall back to the
  platform token.
  """
  def gs1_api_key_changeset(organization, key) do
    key = if is_binary(key), do: String.trim(key), else: key

    case key do
      blank when blank in ["", nil] ->
        change(organization, %{gs1_api_key: nil, gs1_api_key_last4: nil})

      present ->
        change(organization, %{
          gs1_api_key: present,
          gs1_api_key_last4: String.slice(present, -4, 4)
        })
    end
  end

  @doc """
  Changeset that marks the dashboard "Getting started" checklist as
  dismissed, regardless of how many items are still incomplete. Separate
  from completion: an admin can decide the remaining items don't apply
  (or will be done later) without the system silently re-showing the card
  every time they load the dashboard.
  """
  def dismiss_onboarding_checklist_changeset(organization) do
    change(organization, onboarding_checklist_dismissed_at: DateTime.utc_now(:second))
  end

  defp validate_gln_check_digit(changeset) do
    case get_change(changeset, :gln) do
      gln when is_binary(gln) ->
        if Regex.match?(~r/^\d{13}$/, gln) and not gln_check_digit_valid?(gln) do
          add_error(changeset, :gln, "check digit does not match, double-check the number")
        else
          changeset
        end

      _not_changed ->
        changeset
    end
  end

  defp gln_check_digit_valid?(gln) do
    {payload, check} = String.split_at(gln, -1)
    Integer.to_string(ThamaniDawa.GS1.Sscc.mod10_check_digit(payload)) == check
  end

  defp trim_change(changeset, field) do
    update_change(changeset, field, fn
      value when is_binary(value) -> String.trim(value)
      value -> value
    end)
  end

  defp maybe_generate_slug(changeset) do
    if get_field(changeset, :slug) do
      changeset
    else
      generate_slug_from_name(changeset, get_field(changeset, :name))
    end
  end

  defp generate_slug_from_name(changeset, nil), do: changeset

  defp generate_slug_from_name(changeset, name) do
    put_generated_slug(changeset, slugify(name))
  end

  defp put_generated_slug(changeset, ""),
    do: add_error(changeset, :name, "must contain at least one letter or number")

  defp put_generated_slug(changeset, slug), do: put_change(changeset, :slug, slug)

  @doc """
  The normalized key `put_name_key/1` would derive for `name` — lowercased,
  accents stripped, punctuation/whitespace removed — exposed so callers can
  check for a name collision (e.g. right after a GS1 prefix resolves one)
  without building a full changeset.
  """
  @spec name_key(String.t()) :: String.t()
  def name_key(name), do: name |> slugify() |> normalize_name_key()

  defp put_name_key(changeset) do
    case get_field(changeset, :slug) do
      nil -> changeset
      slug -> put_normalized_name_key(changeset, normalize_name_key(slug))
    end
  end

  defp put_normalized_name_key(changeset, ""),
    do: add_error(changeset, :name, "must contain at least one letter or number")

  defp put_normalized_name_key(changeset, name_key),
    do: put_change(changeset, :name_key, name_key)

  defp normalize_name_key(text) do
    text
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/[^a-z0-9]/u, "")
  end

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.trim()
    |> String.normalize(:nfd)
    |> String.replace(~r/[^a-z0-9\s-]/u, " ")
    |> String.replace(~r/[\s-]+/, "-")
    |> String.trim("-")
  end
end
