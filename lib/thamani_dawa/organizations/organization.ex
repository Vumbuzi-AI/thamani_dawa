defmodule ThamaniDawa.Organizations.Organization do
  use Ecto.Schema
  import Ecto.Changeset

  @similar_name_message "An organization with a similar name already exists"
  @slug_index :organizations_slug_index
  @name_key_index :organizations_name_key_index

  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :name_key, :string
    field :license_number, :string
    field :is_active, :boolean, default: true
    field :is_subscription_active, :boolean, default: false
    field :kyc_details, :map, default: %{}

    has_many :sites, ThamaniDawa.Sites.Site
    has_many :users, ThamaniDawa.Accounts.User
    has_many :products, ThamaniDawa.Products.Product
    has_many :suppliers, ThamaniDawa.Suppliers.Supplier
    has_many :patients, ThamaniDawa.Patients.Patient
    has_many :patient_visits, ThamaniDawa.PatientVisits.PatientVisit
    has_many :batches, ThamaniDawa.Batches.Batch
    has_many :prescriptions, ThamaniDawa.Prescriptions.Prescription
    has_many :lab_test_categories, ThamaniDawa.LabTests.LabTestCategory
    has_many :lab_tests, ThamaniDawa.LabTests.LabTest
    has_many :lab_orders, ThamaniDawa.LabOrders.LabOrder
    has_many :lab_order_results, ThamaniDawa.LabOrders.LabOrderResult
    has_many :lab_consumable_usages, ThamaniDawa.LabOrders.LabConsumableUsage

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(organization, attrs) do
    organization
    |> cast(attrs, [:name, :slug, :license_number])
    |> validate_required([:name], message: "Please enter your organization name")
    |> validate_required([:license_number], message: "Please enter your license number")
    |> maybe_generate_slug()
    |> put_name_key()
    |> unique_constraint(:name, message: "An organization with this name already exists")
    |> unique_constraint(:name, name: @slug_index, message: @similar_name_message)
    |> unique_constraint(:name, name: @name_key_index, message: @similar_name_message)
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
