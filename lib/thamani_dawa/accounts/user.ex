defmodule ThamaniDawa.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @roles [:admin, :pharmacist, :lab_technician]

  schema "users" do
    field :organization_id, :id
    field :site_id, :id
    field :invited_by_id, :id
    field :name, :string
    field :email, :string
    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true
    field :hashed_pin, :string, redact: true
    field :pin, :string, virtual: true, redact: true
    field :role, Ecto.Enum, values: @roles
    field :is_active, :boolean, default: true

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
    |> cast(attrs, [:name, :email, :password])
    |> validate_required([:name], message: "Please enter your name")
    |> validate_email()
    |> validate_password(opts)
  end

  @doc """
  Changeset for an admin inviting a staff member (§2.3.2). `organization_id`
  and `invited_by_id` are set explicitly by `ThamaniDawa.Accounts.invite_user/3`
  — never taken from `attrs` — so an admin can only invite staff into their
  own organization. `role` and `site_id` are the admin's own choice on the
  Team screen, so they're cast from `attrs` here. The invited user has no
  password until they accept the invite; see `accept_invite_changeset/2`.
  """
  def invite_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :role, :site_id])
    |> validate_required([:name, :role])
    |> validate_email()
  end

  @doc "Changeset for a user setting their password from an invite link."
  def accept_invite_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_password(opts)
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

  @doc "The valid staff roles, per §7 of project.md."
  def roles, do: @roles

  @doc "Whether the account is active. A deactivated user must not be able to log in or keep an existing session."
  def active?(%__MODULE__{is_active: true}), do: true
  def active?(_user), do: false
end
