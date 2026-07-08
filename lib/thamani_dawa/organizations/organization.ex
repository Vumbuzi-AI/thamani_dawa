defmodule ThamaniDawa.Organizations.Organization do
  use Ecto.Schema
  import Ecto.Changeset

  schema "organizations" do
    field :name, :string
    field :slug, :string
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
    |> validate_required([:name, :license_number])
    |> maybe_generate_slug()
    |> unique_constraint(:name)
    |> unique_constraint(:slug)
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
