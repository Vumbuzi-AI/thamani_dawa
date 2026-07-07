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
      case get_field(changeset, :name) do
        nil -> changeset
        name -> put_change(changeset, :slug, slugify(name) <> "-" <> random_suffix())
      end
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

  defp random_suffix, do: 2 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
end
