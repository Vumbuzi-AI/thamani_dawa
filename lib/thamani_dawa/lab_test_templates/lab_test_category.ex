defmodule ThamaniDawa.LabTestTemplates.LabTestCategory do
  use Ecto.Schema
  import Ecto.Changeset

  schema "lab_test_categories" do
    field :organization_id, :id
    field :name, :string
    field :description, :string
    field :display_order, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(lab_test_category, attrs) do
    lab_test_category
    |> cast(attrs, [:name, :description, :display_order])
    |> validate_required([:name])
    |> unique_constraint(:name, name: :lab_test_categories_organization_id_name_index)
  end
end
