defmodule ThamaniDawa.Patients.Patient do
  use Ecto.Schema
  import Ecto.Changeset

  schema "patients" do
    field :organization_id, :id
    field :full_name, :string
    field :date_of_birth, :date
    field :age, :integer
    field :gender, :string
    field :phone, :string
    field :national_id, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(patient, attrs) do
    patient
    |> cast(attrs, [:full_name, :date_of_birth, :age, :gender, :phone, :national_id])
    |> validate_required([:full_name])
    |> validate_date_of_birth_or_age()
  end

  # Per §4.2: a patient's age may be recorded either as a birth date or a
  # plain age when the exact date isn't known — at least one must be given.
  defp validate_date_of_birth_or_age(changeset) do
    if get_field(changeset, :date_of_birth) || get_field(changeset, :age) do
      changeset
    else
      changeset
      |> add_error(:date_of_birth, "date of birth or age is required")
    end
  end
end
