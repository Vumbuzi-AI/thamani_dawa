defmodule ThamaniDawa.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @staff_roles [:admin, :pharmacist, :lab_technician, :pharma_lab, :distributor]
  @roles @staff_roles ++ [:superadmin]
  @legal_policy_version "2026-10-29"

  schema "users" do
    field :name, :string
    field :email, :string
    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true
    field :accepted_legal_terms, :boolean, virtual: true, default: false
    field :legal_terms_accepted_at, :utc_datetime
    field :legal_policy_version, :string
    field :hashed_pin, :string, redact: true
    field :pin, :string, virtual: true, redact: true
    field :roles, {:array, Ecto.Enum}, values: @roles, default: []
    field :is_active, :boolean, default: true
    field :last_logged_in_at, :utc_datetime
    field :last_logged_out_at, :utc_datetime

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :current_site, ThamaniDawa.Sites.Site
    belongs_to :invited_by, __MODULE__

    many_to_many :sites, ThamaniDawa.Sites.Site,
      join_through: ThamaniDawa.Accounts.UserSite,
      join_defaults: :put_join_organization_id,
      on_replace: :delete

    has_many :invited_users, __MODULE__, foreign_key: :invited_by_id
    has_many :user_tokens, ThamaniDawa.Accounts.UserToken
    has_many :login_sessions, ThamaniDawa.Accounts.UserLoginSession
    has_many :patient_visits, ThamaniDawa.PatientVisits.PatientVisit
    has_many :prescriptions, ThamaniDawa.Prescriptions.Prescription
    has_many :approved_batches, ThamaniDawa.Batches.Batch, foreign_key: :approver_id
    has_many :ordered_lab_orders, ThamaniDawa.LabOrders.LabOrder, foreign_key: :ordered_by_id

    has_many :performed_lab_order_results, ThamaniDawa.LabOrders.LabOrderResult,
      foreign_key: :performed_by_id

    has_many :collected_lab_order_results, ThamaniDawa.LabOrders.LabOrderResult,
      foreign_key: :collected_by_id

    has_many :lab_consumable_usages, ThamaniDawa.LabOrders.LabConsumableUsage,
      foreign_key: :used_by_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for registering the first admin of a brand-new organization.
  `organization_id` and `role` are set explicitly by
  `ThamaniDawa.Accounts.register_user/2`, never taken from `attrs` — a
  caller can never register a user into someone else's organization or hand
  themselves a role.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:name, :email, :password, :accepted_legal_terms])
    |> trim_change(:name)
    |> trim_change(:email)
    |> validate_required([:name], message: "Please enter your name")
    |> validate_email()
    |> validate_password(opts)
    |> validate_legal_consent(opts)
  end

  defp validate_legal_consent(changeset, opts) do
    if Keyword.get(opts, :require_legal_consent, false) do
      changeset
      |> validate_acceptance(:accepted_legal_terms,
        message: "You must accept the Terms of Service and Privacy Policy"
      )
      |> maybe_record_legal_consent()
    else
      changeset
    end
  end

  defp maybe_record_legal_consent(changeset) do
    if get_field(changeset, :accepted_legal_terms) do
      changeset
      |> put_change(:legal_terms_accepted_at, DateTime.utc_now(:second))
      |> put_change(:legal_policy_version, @legal_policy_version)
    else
      changeset
    end
  end

  defp trim_change(changeset, field) do
    update_change(changeset, field, &String.trim/1)
  end

  @doc """
  Changeset for an admin inviting a staff member (§2.3.2). `organization_id`
  and `invited_by_id` are set explicitly by `ThamaniDawa.Accounts.invite_user/3`
  — never taken from `attrs` — so an admin can only invite staff into their
  own organization. `role` is the admin's own choice on the Team screen, so
  it's cast from `attrs` here. Site assignment is a many-to-many
  (`:sites`/`UserSite`) handled separately by `invite_user/3` via
  `put_assoc/3`, since it can't be cast directly. The invited user has no
  password until they accept the invite; see `accept_invite_changeset/2`.
  """
  def invite_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :roles])
    |> validate_required([:name])
    |> validate_staff_roles()
    |> validate_at_least_one_role()
    |> validate_email()
  end

  @doc "Changeset for a user setting their password from an invite link."
  def accept_invite_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password, :accepted_legal_terms])
    |> validate_password(opts)
    |> validate_legal_consent(Keyword.put(opts, :require_legal_consent, true))
  end

  @doc "Changeset for a user resetting an existing password."
  def password_reset_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_password([])
  end

  @doc "Changeset for an admin editing a team member's role and site assignment. Site assignment (`:sites`) is handled separately by `update_user/3` via `put_assoc/3`."
  def edit_changeset(user, attrs) do
    user
    |> cast(attrs, [:roles])
    |> validate_staff_roles()
    |> validate_at_least_one_role()
  end

  defp validate_staff_roles(changeset) do
    validate_change(changeset, :roles, fn :roles, roles ->
      if Enum.all?(roles, &(&1 in @staff_roles)), do: [], else: [roles: "is invalid"]
    end)
  end

  defp validate_at_least_one_role(changeset) do
    already_invalid? = Keyword.has_key?(changeset.errors, :roles)

    if not already_invalid? and get_field(changeset, :roles) in [nil, []] do
      add_error(changeset, :roles, "Choose at least one role")
    else
      changeset
    end
  end

  @doc "Changeset for a user switching which of their assigned sites they're currently operating at."
  def switch_site_changeset(user, attrs) do
    cast(user, attrs, [:current_site_id])
  end

  @doc false
  def put_join_organization_id(user_site, user) do
    %{user_site | organization_id: user.organization_id}
  end

  @doc "Changeset for a user setting or changing their 4-digit counter-side PIN (§7)."
  def pin_changeset(user, attrs) do
    user
    |> cast(attrs, [:pin])
    |> validate_required([:pin])
    |> validate_format(:pin, ~r/^\d{4}$/, message: "must be exactly 4 digits")
    |> maybe_hash_pin()
  end

  defp validate_email(changeset) do
    changeset
    |> validate_required([:email], message: "Please enter your email")
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[a-zA-Z]{2,}$/,
      message: "Please enter a valid email (e.g. you@example.com)"
    )
    |> validate_length(:email, max: 160)
    |> unique_constraint(:email, message: "This email is already registered")
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password], message: "Please choose a password")
    |> validate_length(:password, min: 8, max: 72, message: "Must be at least 8 characters")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  defp maybe_hash_pin(changeset) do
    pin = get_change(changeset, :pin)

    if pin && changeset.valid? do
      changeset
      |> put_change(:hashed_pin, Bcrypt.hash_pwd_salt(pin))
      |> delete_change(:pin)
    else
      changeset
    end
  end

  @doc "Verifies the plaintext password against the stored hash."
  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_user, _password) do
    Bcrypt.no_user_verify()
    false
  end

  @doc "Verifies the plaintext PIN against the stored hash."
  def valid_pin?(%__MODULE__{hashed_pin: hashed_pin}, pin)
      when is_binary(hashed_pin) and byte_size(pin) > 0 do
    Bcrypt.verify_pass(pin, hashed_pin)
  end

  def valid_pin?(_user, _pin) do
    Bcrypt.no_user_verify()
    false
  end

  @doc "The valid organization-staff roles. Platform roles are intentionally excluded."
  def assignable_roles, do: @staff_roles

  @doc "The roles an organization with the given `operating_models` can actually staff, e.g. no `:lab_technician` for a pharmacy-only org."
  def assignable_roles(operating_models) when is_list(operating_models) do
    Enum.filter(@staff_roles, &role_compatible?(&1, operating_models))
  end

  defp role_compatible?(:admin, _models), do: true
  defp role_compatible?(:pharmacist, models), do: :pharmacy in models
  defp role_compatible?(:lab_technician, models), do: :laboratory in models
  defp role_compatible?(:pharma_lab, models), do: :pharmacy in models and :laboratory in models
  defp role_compatible?(:distributor, models), do: :distributor in models

  @doc "Humanized, comma-joined display of a user's roles, e.g. \"Admin, Pharmacist\"."
  def humanize_roles(%__MODULE__{roles: roles}), do: humanize_roles(roles)

  def humanize_roles(roles) when is_list(roles) do
    Enum.map_join(roles, ", ", &Phoenix.Naming.humanize/1)
  end

  @doc "Whether the account is active. A deactivated user must not be able to log in or keep an existing session."
  def active?(%__MODULE__{is_active: true}), do: true
  def active?(_user), do: false
end
