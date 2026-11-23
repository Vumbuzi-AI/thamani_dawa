defmodule ThamaniDawa.Sites.Site do
  use Ecto.Schema
  import Ecto.Changeset

  @activities [:pharmacy, :laboratory, :distribution, :manufacturing]

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

    field :ppb_facility_name, :string
    field :license_number, :string

    field :ppb_verification_status, Ecto.Enum,
      values: [:pending, :verified, :failed],
      default: :pending

    field :ppb_verified_at, :utc_datetime
    field :ppb_license_valid_till, :date
    field :ppb_verification_source, :string

    field :kmlttb_facility_name, :string
    field :kmlttb_license_number, :string

    field :kmlttb_verification_status, Ecto.Enum,
      values: [:pending, :verified, :failed],
      default: :pending

    field :kmlttb_verified_at, :utc_datetime
    field :kmlttb_license_valid_till, :date
    field :kmlttb_verification_source, :string

    belongs_to :organization, ThamaniDawa.Organizations.Organization

    many_to_many :users, ThamaniDawa.Accounts.User, join_through: ThamaniDawa.Accounts.UserSite
    has_many :batches, ThamaniDawa.Batches.Batch
    has_many :patient_visits, ThamaniDawa.PatientVisits.PatientVisit
    has_many :lab_orders, ThamaniDawa.LabOrders.LabOrder
    has_many :payments, ThamaniDawa.Payments.Payment
    has_many :wallet_entries, ThamaniDawa.Payments.WalletEntry

    timestamps(type: :utc_datetime)
  end

  @licensing_fields [
    :name,
    :activities,
    :gln,
    :address,
    :lat,
    :long,
    :is_active,
    :ppb_facility_name,
    :license_number,
    :kmlttb_facility_name,
    :kmlttb_license_number
  ]
  @trimmed_fields [
    :name,
    :gln,
    :ppb_facility_name,
    :license_number,
    :kmlttb_facility_name,
    :kmlttb_license_number
  ]

  @doc false
  def changeset(site, attrs) do
    site
    |> cast(attrs, @licensing_fields)
    |> trim_changes()
    |> validate_required([:name, :activities, :address, :gln])
    |> validate_length(:activities, min: 1, message: "Select at least one activity")
    |> validate_format(:gln, ~r/^\d{13}$/, message: "must be 13 digits")
    |> validate_gln_check_digit()
    |> validate_activity_exclusivity()
    |> unique_constraint(:gln)
  end

  @doc """
  Minimal changeset for system-created sites (signup default site) — no
  address yet. Also requires a PPB facility name and license number
  whenever the selected activities make this a PPB-licensable premises
  (retail pharmacy or wholesale distribution — see `ppb_ftype/1`), and a
  KMLTTB facility name and license number whenever a diagnostic lab is
  among the activities (see `kmlttb_required?/1`) — PPB doesn't license
  labs at all, that's KMLTTB's separate register. A pharmacy+lab site
  requires both.
  """
  def default_changeset(site, attrs) do
    site
    |> cast(attrs, @licensing_fields ++ [:gln_verified_at, :gln_verification_source])
    |> trim_changes()
    |> validate_required([:name, :activities])
    |> validate_length(:activities, min: 1, message: "Select at least one activity")
    |> validate_format(:gln, ~r/^\d{13}$/, message: "must be 13 digits")
    |> validate_gln_check_digit()
    |> validate_activity_exclusivity()
    |> validate_ppb_fields()
    |> validate_kmlttb_fields()
    |> unique_constraint(:gln)
  end

  defp trim_changes(changeset) do
    Enum.reduce(@trimmed_fields, changeset, &trim_change(&2, &1))
  end

  # PPB licenses retail pharmacy and wholesale distribution premises
  # separately — the same physical site can never hold both at once, so
  # these two activities are mutually exclusive (diagnostic lab work is
  # unaffected; it isn't a PPB-licensed activity at all).
  defp validate_activity_exclusivity(changeset) do
    activities = get_field(changeset, :activities) || []

    cond do
      :pharmacy in activities and :distribution in activities ->
        add_error(
          changeset,
          :activities,
          "A location can be licensed for retail pharmacy or wholesale distribution, not both — PPB requires separate premises for each"
        )

      :manufacturing in activities and :pharmacy in activities ->
        add_error(
          changeset,
          :activities,
          "A location can be licensed for manufacturing or retail pharmacy, not both — PPB requires separate premises for each"
        )

      :manufacturing in activities and :laboratory in activities ->
        add_error(
          changeset,
          :activities,
          "A location can be licensed for manufacturing or diagnostic lab work, not both — PPB requires separate premises for each"
        )

      true ->
        changeset
    end
  end

  defp validate_ppb_fields(changeset) do
    activities = get_field(changeset, :activities) || []

    if ppb_ftype(activities) do
      validate_required(changeset, [:ppb_facility_name, :license_number],
        message: "is required to verify this location's PPB license"
      )
    else
      changeset
    end
  end

  defp validate_kmlttb_fields(changeset) do
    activities = get_field(changeset, :activities) || []

    if kmlttb_required?(activities) do
      validate_required(changeset, [:kmlttb_facility_name, :kmlttb_license_number],
        message: "is required to verify this location's KMLTTB license"
      )
    else
      changeset
    end
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

  @doc "Returns true if the site is used for manufacturing."
  def manufacturer?(%__MODULE__{activities: activities}) when is_list(activities),
    do: :manufacturing in activities

  def manufacturer?(_), do: false

  @doc """
  The PPB search `ftype` this site's activities call for — `"retail"` for a
  pharmacy, `"wholesale"` for a distributor, `"manufacturer"` for a
  manufacturing site, or `nil` if the site isn't PPB-licensable at all
  (lab-only, or no activities chosen yet). Accepts either a `%Site{}`, a
  list of activity atoms, or a list of activity strings (raw,
  not-yet-cast form params), so both schema-backed and in-progress signup
  state can use it.
  """
  def ppb_ftype(%__MODULE__{activities: activities}), do: ppb_ftype(activities)

  def ppb_ftype(activities) when is_list(activities) do
    activities = Enum.map(activities, &to_string/1)

    cond do
      "pharmacy" in activities -> "retail"
      "distribution" in activities -> "wholesale"
      "manufacturing" in activities -> "manufacturer"
      true -> nil
    end
  end

  def ppb_ftype(_activities), do: nil

  @doc """
  Returns true if this site's activities call for a KMLTTB lab license —
  diagnostic lab work, whether standalone or alongside a retail pharmacy.
  Accepts the same shapes as `ppb_ftype/1`.
  """
  def kmlttb_required?(%__MODULE__{activities: activities}), do: kmlttb_required?(activities)

  def kmlttb_required?(activities) when is_list(activities) do
    "laboratory" in Enum.map(activities, &to_string/1)
  end

  def kmlttb_required?(_activities), do: false

  @doc """
  Whether a user holding any of `roles` could work at this site: the site's
  activities must support at least one of the role's operations. Admins and
  superadmins administer any site. Keeps site assignments from stranding a
  staff member at a location whose panel none of their roles can operate.
  """
  def role_compatible?(roles, %__MODULE__{} = site) when is_list(roles) do
    Enum.any?(roles, fn
      :admin -> true
      :superadmin -> true
      :pharmacist -> pharmacy?(site)
      :lab_technician -> lab?(site)
      :distributor -> distribution?(site)
      :manufacturer -> manufacturer?(site)
      :pharma_lab -> pharmacy?(site) or lab?(site)
      _other -> false
    end)
  end

  def role_compatible?(_roles, _site), do: false
end
