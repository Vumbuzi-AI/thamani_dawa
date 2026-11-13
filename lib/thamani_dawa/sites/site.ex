defmodule ThamaniDawa.Sites.Site do
  use Ecto.Schema
  import Ecto.Changeset

  @activities [:pharmacy, :laboratory, :distribution]

  schema "sites" do
    field :name, :string
    field :activities, {:array, Ecto.Enum}, values: @activities
    field :gln, :string
    field :gln_verified_at, :utc_datetime
    field :gln_verification_source, :string
    field :address, :string
    field :lat, :float
    field :long, :float
    field :is_active, :boolean, default: true

    belongs_to :organization, ThamaniDawa.Organizations.Organization

    many_to_many :users, ThamaniDawa.Accounts.User, join_through: ThamaniDawa.Accounts.UserSite
    has_many :batches, ThamaniDawa.Batches.Batch
    has_many :patient_visits, ThamaniDawa.PatientVisits.PatientVisit
    has_many :lab_orders, ThamaniDawa.LabOrders.LabOrder
    has_many :payments, ThamaniDawa.Payments.Payment
    has_many :wallet_entries, ThamaniDawa.Payments.WalletEntry

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(site, attrs) do
    site
    |> cast(attrs, [:name, :activities, :gln, :address, :lat, :long, :is_active])
    |> trim_change(:name)
    |> trim_change(:gln)
    |> validate_required([:name, :activities, :address])
    |> validate_length(:activities, min: 1, message: "Select at least one activity")
    |> validate_format(:gln, ~r/^\d{13}$/, message: "must be 13 digits")
    |> validate_gln_check_digit()
    |> unique_constraint(:gln)
  end

  @doc "Minimal changeset for system-created sites (signup default site) — no address yet."
  def default_changeset(site, attrs) do
    site
    |> cast(attrs, [:name, :activities, :gln, :address, :lat, :long, :is_active])
    |> trim_change(:name)
    |> trim_change(:gln)
    |> validate_required([:name, :activities])
    |> validate_length(:activities, min: 1, message: "Select at least one activity")
    |> validate_format(:gln, ~r/^\d{13}$/, message: "must be 13 digits")
    |> validate_gln_check_digit()
    |> unique_constraint(:gln)
  end

  defp trim_change(changeset, field) do
    update_change(changeset, field, fn
      value when is_binary(value) -> String.trim(value)
      value -> value
    end)
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

  @doc "The activities a site may perform, mirroring Organization.operating_models."
  def activities, do: @activities

  @doc "Returns true if the site is capable of pharmacy work."
  def pharmacy?(%__MODULE__{activities: activities}) when is_list(activities),
    do: :pharmacy in activities

  def pharmacy?(_), do: false

  @doc "Returns true if the site is capable of lab work."
  def lab?(%__MODULE__{activities: activities}) when is_list(activities),
    do: :laboratory in activities

  def lab?(_), do: false

  @doc "Returns true if the site is used for distribution/warehousing."
  def distribution?(%__MODULE__{activities: activities}) when is_list(activities),
    do: :distribution in activities

  def distribution?(_), do: false
end
