defmodule ThamaniDawa.Patients.Patient do
  use Ecto.Schema
  import Ecto.Changeset

  schema "patients" do
    field :full_name, :string
    field :date_of_birth, :date
    field :gender, :string
    field :phone, :string
    field :national_id, :string
    field :gsrn, :integer

    belongs_to :organization, ThamaniDawa.Organizations.Organization

    has_many :patient_visits, ThamaniDawa.PatientVisits.PatientVisit

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(patient, attrs) do
    patient
    |> cast(attrs, [:full_name, :date_of_birth, :gender, :phone, :national_id, :gsrn])
    |> validate_required([:full_name, :gsrn, :date_of_birth, :gender, :phone])
    |> validate_format(:national_id, ~r/^\d*$/, message: "must contain only numbers")
    |> validate_length(:national_id, is: 8, message: "must be exactly 8 characters")
    |> validate_format(:phone, ~r/^(?:\+254|0)[17]\d{8}$/,
      message: "must be a valid Kenyan phone number (e.g. 0712345678 or +254712345678)"
    )
    |> validate_date_of_birth_not_in_future()
  end

  defp validate_date_of_birth_not_in_future(changeset) do
    validate_change(changeset, :date_of_birth, fn :date_of_birth, date ->
      if Date.compare(date, Date.utc_today()) == :gt do
        [date_of_birth: "can't be in the future"]
      else
        []
      end
    end)
  end

  @doc """
  Derives the patient's current age in whole years from `date_of_birth`, as
  of `today` (defaults to the real current date). Returns `nil` when
  `date_of_birth` is `nil`. Age is never persisted — this is the only
  source of truth, computed fresh wherever it's displayed.
  """
  def age(patient, today \\ Date.utc_today())
  def age(%__MODULE__{date_of_birth: nil}, _today), do: nil

  def age(%__MODULE__{date_of_birth: dob}, today) do
    years = today.year - dob.year
    if {today.month, today.day} < {dob.month, dob.day}, do: years - 1, else: years
  end

  @doc """
  Approximates a date of birth from an age alone, for migrating legacy
  records that only ever captured age (never a real birth date). Documented
  convention: January 1st of the birth year implied by `age` years before
  `reference_date` (defaults to today) — an explicit placeholder date, not
  an attempt to guess the real one.
  """
  def approximate_date_of_birth_from_age(age, reference_date \\ Date.utc_today())
      when is_integer(age) and age >= 0 do
    Date.new!(reference_date.year - age, 1, 1)
  end
end
