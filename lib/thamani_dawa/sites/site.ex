defmodule ThamaniDawa.Sites.Site do
  use Ecto.Schema
  import Ecto.Changeset

  @site_types [:pharmacy, :lab, :pharmacy_lab, :warehouse]

  schema "sites" do
    field :name, :string
    field :site_type, Ecto.Enum, values: @site_types
    field :gln, :string
    field :address, :string
    field :lat, :float
    field :long, :float
    field :is_active, :boolean, default: true

    belongs_to :organization, ThamaniDawa.Organizations.Organization

    has_many :users, ThamaniDawa.Accounts.User
    has_many :batches, ThamaniDawa.Batches.Batch
    has_many :patient_visits, ThamaniDawa.PatientVisits.PatientVisit
    has_many :lab_orders, ThamaniDawa.LabOrders.LabOrder

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(site, attrs) do
    site
    |> cast(attrs, [:name, :site_type, :gln, :address, :lat, :long, :is_active])
    |> validate_required([:name, :site_type, :gln, :address])
    |> unique_constraint(:gln)
  end

  @doc "Minimal changeset for system-created sites (signup default site) — no gln/address yet."
  def default_changeset(site, attrs) do
    site
    |> cast(attrs, [:name, :site_type, :lat, :long, :is_active])
    |> validate_required([:name, :site_type])
  end

  @doc "The valid site types, per §4.1 of project.md."
  def site_types, do: @site_types

  @doc "Returns true if the site is capable of pharmacy work."
  def pharmacy?(%__MODULE__{site_type: type}) when type in [:pharmacy, :pharmacy_lab], do: true
  def pharmacy?(_), do: false

  @doc "Returns true if the site is capable of lab work."
  def lab?(%__MODULE__{site_type: type}) when type in [:lab, :pharmacy_lab], do: true
  def lab?(_), do: false
end
