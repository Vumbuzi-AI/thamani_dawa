defmodule ThamaniDawa.LabTests.LabTestCategory do
  use Ecto.Schema
  import Ecto.Changeset

  schema "lab_test_categories" do
    field :name, :string
    field :description, :string
    field :display_order, :integer, default: 0

    belongs_to :organization, ThamaniDawa.Organizations.Organization

    has_many :lab_tests, ThamaniDawa.LabTests.LabTest, foreign_key: :category_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(lab_test_category, attrs) do
    lab_test_category
    |> cast(attrs, [:name, :description, :display_order])
    |> validate_required([:name])
    |> unique_constraint([:organization_id, :name], message: "already exists")
  end
end
