defmodule ThamaniDawa.Organizations.Organization do
  use Ecto.Schema
  import Ecto.Changeset

  # The signup/settings forms only render a `:name` input, not `:slug` or
  # `:name_key` -- every uniqueness error below is deliberately attached to
  # `:name` (via `unique_constraint`'s `:name` option pointing at the
  # underlying DB index) so the message actually reaches the user, even
  # though the collision is on a derived field.
  @similar_name_message "An organization with a similar name already exists"

  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :name_key, :string
    field :license_number, :string
    field :is_active, :boolean, default: true
    field :is_subscription_active, :boolean, default: false
    field :kyc_details, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(organization, attrs) do
    organization
    |> cast(attrs, [
      :name,
      :slug,
      :license_number,
      :is_active,
      :is_subscription_active,
      :kyc_details
    ])
    |> validate_required([:name], message: "Please enter your organization name")
    |> validate_required([:license_number], message: "Please enter your license number")
    |> maybe_generate_slug()
    |> put_name_key()
    |> unique_constraint(:name, message: "An organization with this name already exists")
    |> unique_constraint(:name, name: :organizations_slug_index, message: @similar_name_message)
    |> unique_constraint(:name,
      name: :organizations_name_key_index,
      message: @similar_name_message
    )
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

  # Derived from the (already accent/case-normalized) slug, with separators
  # stripped entirely -- so "PharmaPlus", "Pharma-Plus", "Pharma Plus", and
  # "pharmaplus" all collapse to the same key and are treated as duplicates,
  # even though they'd produce different human-readable slugs.
  defp put_name_key(changeset) do
    case get_field(changeset, :slug) do
      nil -> changeset
      slug -> put_change(changeset, :name_key, String.replace(slug, "-", ""))
    end
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
