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
    field :gsrn, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(patient, attrs) do
    patient
    |> cast(attrs, [:full_name, :date_of_birth, :age, :gender, :phone, :national_id, :gsrn])
    |> validate_required([:full_name, :gsrn])
    |> validate_format(:national_id, ~r/^\d*$/, message: "must contain only numbers")
    |> validate_length(:national_id, is: 8, message: "must be exactly 8 characters")
    |> validate_format(:phone, ~r/^(?:\+254|0)[17]\d{8}$/,
      message: "must be a valid Kenyan phone number (e.g. 0712345678 or +254712345678)"
    )
    |> validate_date_of_birth_or_age()
  end

  defp validate_date_of_birth_or_age(changeset) do
    if get_field(changeset, :date_of_birth) || get_field(changeset, :age) do
      changeset
    else
      changeset
      |> add_error(:date_of_birth, "date of birth or age is required")
    end
  end
end
