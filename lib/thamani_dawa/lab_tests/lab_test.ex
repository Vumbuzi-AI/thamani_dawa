defmodule ThamaniDawa.LabTests.LabTest do
  use Ecto.Schema
  import Ecto.Changeset

  @categories [
    "Haematology",
    "Biochemistry",
    "Microbiology",
    "Serology",
    "Immunology",
    "Molecular",
    "Histopathology",
    "Urinalysis",
    "Parasitology"
  ]

  schema "lab_tests" do
    field :organization_id, :id
    field :name, :string
    field :price, :decimal
    field :is_active, :boolean, default: true
    field :field_definitions, :map
    field :category, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(lab_test, attrs) do
    lab_test
    |> cast(attrs, [:name, :price, :is_active, :field_definitions, :category])
    |> validate_required([:name, :field_definitions, :category])
    |> validate_inclusion(:category, @categories,
      message: "must be one of the approved categories"
    )
  end

  @doc "The approved test categories, in display order."
  def categories, do: @categories
end
