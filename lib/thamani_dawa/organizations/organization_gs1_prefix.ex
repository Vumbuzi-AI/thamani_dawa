defmodule ThamaniDawa.Organizations.OrganizationGs1Prefix do
  use Ecto.Schema
  import Ecto.Changeset

  schema "organization_gs1_prefixes" do
    field :prefix, :string

    field :verification_status, Ecto.Enum,
      values: [:pending, :verified, :failed],
      default: :pending

    field :is_primary, :boolean, default: false
    field :verified_at, :utc_datetime

    belongs_to :organization, ThamaniDawa.Organizations.Organization

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for adding a new GS1 company prefix to an organization."
  def changeset(organization_gs1_prefix, attrs) do
    organization_gs1_prefix
    |> cast(attrs, [:organization_id, :prefix, :is_primary])
    |> update_change(:prefix, &trim/1)
    |> validate_required([:organization_id, :prefix])
    |> validate_format(:prefix, ~r/^\d{6,10}$/, message: "must be 6 to 10 digits")
    |> unique_constraint(:prefix,
      name: :organization_gs1_prefixes_organization_id_prefix_index,
      message: "already added to this organization"
    )
    |> unique_constraint([:organization_id],
      name: :one_primary_prefix_per_organization,
      message: "there is already a primary GS1 company prefix"
    )
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value
end
