defmodule ThamaniDawa.Sites.Site do
  use Ecto.Schema
  import Ecto.Changeset

  @site_types [:pharmacy, :lab, :warehouse]

  schema "sites" do
    field :organization_id, :id
    field :name, :string
    field :site_type, Ecto.Enum, values: @site_types
    field :gln, :string
    field :address, :string
    field :is_active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(site, attrs) do
    site
    |> cast(attrs, [:name, :site_type, :gln, :address, :is_active])
    |> validate_required([:name, :site_type])
    |> unique_constraint(:gln)
  end

  @doc "The valid site types, per §4.1 of project.md."
  def site_types, do: @site_types
end
