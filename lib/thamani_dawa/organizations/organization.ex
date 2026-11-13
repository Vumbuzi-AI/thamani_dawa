defmodule ThamaniDawa.Organizations.Organization do
  use Ecto.Schema
  import Ecto.Changeset

  @similar_name_message "An organization with a similar name already exists"
  @slug_index :organizations_slug_index
  @name_key_index :organizations_name_key_index
  @operating_models [:pharmacy, :laboratory, :distributor]

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
    field :kyc_details, :map, default: %{}
    field :next_requisition_number, :integer, default: 0
    field :gs1_company_prefix, :string

    field :gs1_prefix_verification_status, Ecto.Enum,
      values: [:pending, :verified, :failed],
      default: :pending

    field :gln, :string
    field :gln_verified_at, :utc_datetime
    field :gln_verification_source, :string
    field :next_sscc_serial, :integer, default: 0
    field :next_goods_receipt_number, :integer, default: 0
    field :serialisation_type, :string
    field :vat_registered, :boolean, default: true
    field :next_serial_invoice_number, :integer, default: 0

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
    |> cast(attrs, [:name, :slug, :license_number, :operating_models, :gs1_company_prefix])
    |> trim_change(:name)
    |> trim_change(:license_number)
    |> trim_change(:gs1_company_prefix)
    |> validate_required([:name], message: "Please enter your organization name")
    |> validate_required([:license_number], message: "Please enter your license number")
    |> validate_length(:operating_models,
      min: 1,
      message: "Select at least one operating model"
    )
    |> validate_format(:gs1_company_prefix, ~r/^\d{6,10}$/, message: "must be 6 to 10 digits")
    |> maybe_generate_slug()
    |> put_name_key()
    |> unique_constraint(:name, message: "An organization with this name already exists")
    |> unique_constraint(:name, name: @slug_index, message: @similar_name_message)
    |> unique_constraint(:name, name: @name_key_index, message: @similar_name_message)
  end

  @doc """
  Changeset for onboarding: same rules as `changeset/2`, plus a GS1 company
  prefix, always required. Dispensing (pharmacy) and distribution
  (distributor) events build org-prefixed identifiers directly, but even a
  laboratory-only organization needs it: goods receiving (`Epcis.record_goods_receipt/1`)
  requires the org's GS1 prefix regardless of operating model.
  """
  def signup_changeset(organization, attrs) do
    organization
    |> changeset(attrs)
    |> validate_gs1_company_prefix()
  end

  @doc "The operating models an organization may enable during onboarding."
  def operating_models, do: @operating_models

  @doc "Whether the organization operates as a distributor."
  def distributor?(%__MODULE__{operating_models: models}) when is_list(models),
    do: :distributor in models

  def distributor?(_organization), do: false

  @doc """
  Whether a GS1 company prefix must be present. Always true — every
  operating model eventually posts a goods receipt, which requires it
  regardless of operating model.
  """
  def gs1_prefix_required?(_organization), do: true

  @doc "Changeset for the organization's GS1 identifiers (company prefix and GLN)."
  def gs1_settings_changeset(organization, attrs) do
    organization
    |> cast(attrs, [:gs1_company_prefix, :gln])
    |> trim_change(:gs1_company_prefix)
    |> trim_change(:gln)
    |> validate_format(:gs1_company_prefix, ~r/^\d{6,10}$/, message: "must be 6 to 10 digits")
    |> validate_format(:gln, ~r/^\d{13}$/, message: "must be a 13-digit GLN")
    |> validate_gln_check_digit()
  end

  @doc "Changeset for the organization details editable from the settings page (licence, VAT status)."
  def details_changeset(organization, attrs) do
    organization
    |> cast(attrs, [:license_number, :vat_registered])
    |> trim_change(:license_number)
    |> validate_required([:license_number], message: "Please enter your license number")
  end

  @doc """
  Changeset for the organization settings editable from the settings page.
  The GS1 company prefix is deliberately excluded — it's baked into every
  GTIN/SSCC already issued under it, so changing it after the fact would
  desync those identifiers from the org record. It's set once at onboarding.
  """
  def settings_changeset(organization, attrs) do
    organization
    |> cast(attrs, [:license_number, :vat_registered, :gln])
    |> trim_change(:license_number)
    |> trim_change(:gln)
    |> validate_required([:license_number], message: "Please enter your license number")
    |> validate_format(:gln, ~r/^\d{13}$/, message: "must be a 13-digit GLN")
    |> validate_gln_check_digit()
  end

  defp validate_gln_check_digit(changeset) do
    case get_change(changeset, :gln) do
      gln when is_binary(gln) ->
        if Regex.match?(~r/^\d{13}$/, gln) and not gln_check_digit_valid?(gln) do
          add_error(changeset, :gln, "check digit does not match — double-check the number")
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

  defp validate_gs1_company_prefix(changeset) do
    if prefix_blank?(get_field(changeset, :gs1_company_prefix)) do
      add_error(changeset, :gs1_company_prefix, "Please enter your GS1 company prefix")
    else
      changeset
    end
  end

  defp prefix_blank?(nil), do: true
  defp prefix_blank?(""), do: true
  defp prefix_blank?(_prefix), do: false

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
